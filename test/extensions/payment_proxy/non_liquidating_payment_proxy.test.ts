import { expect } from 'chai';
import { ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbEthPaymentTerminal from '../../../artifacts/contracts/JBETHPaymentTerminal.sol/JBETHPaymentTerminal.json';
import jbOperatorStore from '../../../artifacts/contracts/JBOperatorStore.sol/JBOperatorStore.json';
import jbProjects from '../../../artifacts/contracts/JBProjects.sol/JBProjects.json';
import erc20abi from '../erc20.abi.json';

describe('Non-liquidating Payment Processor Tests', () => {
    const MANAGE_PAYMENTS = 1002;
    const TOKENS_ETH = '0x000000000000000000000000000000000000EEEe';

    let deployer;
    let accounts;
    let paymentProcessor;
    let acceptableToken;
    let unacceptableToken;

    before(async () => {
        const projectId = 99;

        [deployer, ...accounts] = await ethers.getSigners();

        let [
            mockJbDirectory,
            mockJbOperatorStore,
            mockJbProjects,
            mockJbTerminal
        ] = await Promise.all([
            deployMockContract(deployer, jbDirectory.abi),
            deployMockContract(deployer, jbOperatorStore.abi),
            deployMockContract(deployer, jbProjects.abi),
            deployMockContract(deployer, jbEthPaymentTerminal.abi)
        ]);

        [
            acceptableToken,
            unacceptableToken
        ] = await Promise.all([
            deployMockContract(deployer, erc20abi),
            deployMockContract(deployer, erc20abi)]);

        const tokenLiquidatorFactory = await ethers.getContractFactory('TokenLiquidator');
        const tokenLiquidator = await tokenLiquidatorFactory.connect(deployer).deploy(
            mockJbDirectory.address,
            mockJbOperatorStore.address,
            mockJbProjects.address,
            500,
            3000
        );

        const paymentProcessorFactory = await ethers.getContractFactory('PaymentProcessor');
        paymentProcessor = await paymentProcessorFactory.connect(deployer).deploy(
            mockJbDirectory.address,
            mockJbOperatorStore.address,
            mockJbProjects.address,
            tokenLiquidator.address,
            projectId,
            false, // ignoreFailures,
            false // defaultLiquidation
        );
        await paymentProcessor.deployed();

        await helpers.setBalance(deployer.address, '0x56BC75E2D63100000'); // 100000000000000000000

        await mockJbDirectory.mock.isTerminalOf.withArgs(projectId, mockJbTerminal.address).returns(true);
        await mockJbDirectory.mock.controllerOf.withArgs(projectId).returns(deployer.address);
        await mockJbDirectory.mock.primaryTerminalOf.withArgs(projectId, TOKENS_ETH).returns(mockJbTerminal.address);
        await mockJbDirectory.mock.primaryTerminalOf.withArgs(projectId, acceptableToken.address).returns(mockJbTerminal.address);

        await mockJbTerminal.mock.pay.returns(0);

        await mockJbProjects.mock.ownerOf.withArgs(projectId).returns(deployer.address);

        await mockJbOperatorStore.mock.hasPermission.withArgs(deployer.address, deployer.address, projectId, MANAGE_PAYMENTS).returns(true);
        await mockJbOperatorStore.mock.hasPermission.withArgs(deployer.address, deployer.address, 0, MANAGE_PAYMENTS).returns(true);

        await acceptableToken.mock.transferFrom.returns(true);
        await acceptableToken.mock.approve.returns(true);

        await paymentProcessor.connect(deployer).setTokenPreferences(acceptableToken.address, true, false)
        // await paymentProcessor.connect(deployer).setTokenPreferences(unacceptableToken.address, false, false) // an unregistered token is implicitly unapproved
    });

    it('Receive direct payment in eth, forward it to a terminal', async () => {
        await expect(deployer.sendTransaction({ to: paymentProcessor.address, value: ethers.utils.parseEther('1.0') }))
            .not.to.be.reverted;
    });

    it('Receive payment in eth, forward it to a terminal', async () => {
        await expect(paymentProcessor.connect(accounts[0])['processPayment(string,bytes)']('', 0x0, { value: ethers.utils.parseEther('1.0') }))
            .not.to.be.reverted;
    });

    it('Receive payment in approved token, forward it to a terminal', async () => {
        await expect(paymentProcessor.connect(accounts[0])
        ['processPayment(address,uint256,uint256,string,bytes)'](acceptableToken.address, 100, 0, '', 0x0))
            .not.to.be.reverted;
    });

    it('Receive payment in unapproved token, reject it', async () => {
        await expect(paymentProcessor.connect(accounts[0])
        ['processPayment(address,uint256,uint256,string,bytes)'](unacceptableToken.address, 100, 0, '', 0x0))
            .to.be.revertedWithCustomError(paymentProcessor, 'PAYMENT_FAILURE');
    });
});