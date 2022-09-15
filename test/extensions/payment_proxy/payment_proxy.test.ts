import { expect } from 'chai';
import { ethers } from 'hardhat';
import { smock } from '@defi-wonderland/smock';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbOperatorStore from '../../../artifacts/contracts/JBOperatorStore.sol/JBOperatorStore.json';
import jbProjects from '../../../artifacts/contracts/JBProjects.sol/JBProjects.json';
import erc20abi from '../erc20.abi.json';

describe('Payment Processor Privileged Operation Tests', () => {
    const MANAGE_PAYMENTS = 1002;

    let deployer;
    let accounts;
    let paymentProcessor;
    let mockToken;

    before(async () => {
        const projectId = 99;

        [deployer, ...accounts] = await ethers.getSigners();

        let [
            mockJbDirectory,
            mockJbOperatorStore,
            mockJbProjects
        ] = await Promise.all([
            deployMockContract(deployer, jbDirectory.abi),
            deployMockContract(deployer, jbOperatorStore.abi),
            deployMockContract(deployer, jbProjects.abi)
        ]);

        mockToken = await smock.fake(erc20abi);
        mockToken.transfer.returns();

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
            true, // ignoreFailures,
            false // defaultLiquidation
        );
        await paymentProcessor.deployed();

        await mockJbDirectory.mock.controllerOf.withArgs(projectId).returns(deployer.address);
        await mockJbProjects.mock.ownerOf.withArgs(projectId).returns(deployer.address);
        await mockJbOperatorStore.mock.hasPermission.withArgs(deployer.address, deployer.address, projectId, MANAGE_PAYMENTS)
            .returns(true);
        await mockJbOperatorStore.mock.hasPermission.withArgs(deployer.address, deployer.address, 0, MANAGE_PAYMENTS)
            .returns(true);
        await mockJbOperatorStore.mock.hasPermission.withArgs(accounts[0].address, deployer.address, projectId, MANAGE_PAYMENTS)
            .returns(true);
        await mockJbOperatorStore.mock.hasPermission.withArgs(accounts[0].address, deployer.address, 0, MANAGE_PAYMENTS)
            .returns(false);
        await mockJbOperatorStore.mock.hasPermission.withArgs(accounts[1].address, deployer.address, projectId, MANAGE_PAYMENTS)
            .returns(false);
        await mockJbOperatorStore.mock.hasPermission.withArgs(accounts[1].address, deployer.address, 0, MANAGE_PAYMENTS)
            .returns(false);
    });

    it('setTokenPreferences()', async () => {
        await expect(paymentProcessor.connect(deployer).setTokenPreferences(mockToken.address, false, true))
            .not.to.be.reverted;
        await expect(paymentProcessor.connect(deployer).setTokenPreferences(mockToken.address, true, false))
            .not.to.be.reverted;

        await expect(paymentProcessor.connect(accounts[1]).setTokenPreferences(mockToken.address, false, true))
            .to.be.revertedWithCustomError(paymentProcessor, 'UNAUTHORIZED');
    });

    it('setDefaults()', async () => {
        await expect(paymentProcessor.connect(deployer).setDefaults(true, true))
            .not.to.be.reverted;

        await expect(paymentProcessor.connect(accounts[1]).setDefaults(true, true))
            .to.be.revertedWithCustomError(paymentProcessor, 'UNAUTHORIZED');
    });

    it('transferBalance()', async () => {
        await expect(paymentProcessor.connect(deployer).transferBalance(deployer.address, 100))
            .to.be.revertedWith('INVALID_AMOUNT()');

        const hundredEth = ethers.utils.parseEther('100').toHexString();
        await helpers.setBalance(paymentProcessor.address, hundredEth);

        await expect(paymentProcessor.connect(deployer).transferBalance(deployer.address, 100))
            .not.to.be.reverted;

        await expect(paymentProcessor.connect(accounts[1]).transferBalance(accounts[1].address, 100))
            .to.be.revertedWithCustomError(paymentProcessor, 'UNAUTHORIZED');

        await expect(paymentProcessor.connect(deployer).transferBalance(ethers.constants.AddressZero, 100))
            .to.be.revertedWithCustomError(paymentProcessor, 'INVALID_ADDRESS');
    });

    it('transferTokens()', async () => {
        await expect(paymentProcessor.connect(deployer).transferTokens(deployer.address, mockToken.address, 100))
            .not.to.be.reverted;

        await expect(paymentProcessor.connect(deployer).transferTokens(ethers.constants.AddressZero, mockToken.address, 100))
            .to.be.revertedWithCustomError(paymentProcessor, 'INVALID_ADDRESS');

        await expect(paymentProcessor.connect(accounts[1]).transferTokens(accounts[1].address, mockToken.address, 100))
            .to.be.revertedWithCustomError(paymentProcessor, 'UNAUTHORIZED');
    });
});
