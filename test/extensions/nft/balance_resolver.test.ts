import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

enum PriceFunction {
    LINEAR,
    EXP,
    CONSTANT
}

describe('BalancePriceResolver tests', () => {
    const basicProjectId = 99;
    const basicUnitPrice = ethers.utils.parseEther('0.001');
    const priceCap = ethers.utils.parseEther('1');

    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];

    let directory;
    let basicToken: any;
    let balancePriceResolver: any;

    before('Initialize accounts', async () => {
        [deployer, ...accounts] = await ethers.getSigners();
    });

    before('Setup JBX components', async () => {
        const jbxJbTokensEth = '0x000000000000000000000000000000000000EEEe';

        directory = await deployMockContract(deployer, jbDirectory.abi);
        const terminal = await deployMockContract(deployer, jbTerminal.abi);

        await terminal.mock.pay.returns(0);
        await directory.mock.isTerminalOf.withArgs(basicProjectId, terminal.address).returns(true);
        await directory.mock.primaryTerminalOf.withArgs(basicProjectId, jbxJbTokensEth).returns(terminal.address);
    });

    before('Initialize contracts', async () => {
        const basicName = 'Test NFT'
        const basicSymbol = 'NFT';
        const basicBaseUri = 'ipfs://hidden';
        const basicContractUri = 'ipfs://metadata';
        const basicMaxSupply = 20;
        const basicMintAllowance = 10
        const basicMintPeriodStart = 0;
        const basicMintPeriodEnd = Math.floor((Date.now() / 1000) + 24 * 60 * 60);

        const nfTokenFactory = await ethers.getContractFactory('NFToken');
        basicToken = await nfTokenFactory
            .connect(deployer)
            .deploy(
                basicName,
                basicSymbol,
                basicBaseUri,
                basicContractUri,
                basicProjectId,
                directory.address,
                basicMaxSupply,
                basicUnitPrice,
                basicMintAllowance,
                basicMintPeriodStart,
                basicMintPeriodEnd
            );
    });

    it('Assign linear price resolver, fee 1st, n/2 until 2 free', async () => {
        const balancePriceResolverFactory = await ethers.getContractFactory('BalancePriceResolver');
        balancePriceResolver = await balancePriceResolverFactory
            .connect(deployer)
            .deploy(basicUnitPrice, true, 2, 2, priceCap, PriceFunction.LINEAR, 2, 10);

        await expect(basicToken.connect(accounts[0]).updatePriceResolver(balancePriceResolver.address))
            .to.be.reverted;
        await expect(basicToken.connect(deployer).updatePriceResolver(balancePriceResolver.address))
            .not.to.be.reverted;

        expect(await basicToken.priceResolver()).to.equal(balancePriceResolver.address);
    });

    it('Get price for 1st token', async () => {
        expect(await balancePriceResolver.getPrice(basicToken.address, accounts[0].address, 0))
            .to.equal(0);

        await basicToken.connect(accounts[0])['mint()']();
        expect(await basicToken.balanceOf(accounts[0].address)).to.equal(1);

        expect(await balancePriceResolver.getPrice(basicToken.address, accounts[0].address, 0))
            .to.equal(0);
    });

    it('Free nth mint: 2', async () => {
        await basicToken.connect(accounts[0])['mint()']();
        expect(await basicToken.balanceOf(accounts[0].address)).to.equal(2);
    });

    it('Free nth mint: 4', async () => {
        await basicToken.connect(accounts[0])['mint()']({value: basicUnitPrice});

        expect(await balancePriceResolver.getPriceWithParams(basicToken.address, accounts[0].address, 0, '0x00'))
            .to.equal(0);

        await basicToken.connect(accounts[0])['mint()']();
        
        expect(await basicToken.balanceOf(accounts[0].address)).to.equal(4);

        await basicToken.connect(accounts[0])['mint()']({value: basicUnitPrice});
        await basicToken.connect(accounts[0])['mint()']({value: basicUnitPrice});
        expect(await basicToken.balanceOf(accounts[0].address)).to.equal(6);
    });

    it('Assign constant price resolver', async () => {
        const balancePriceResolverFactory = await ethers.getContractFactory('BalancePriceResolver');
        balancePriceResolver = await balancePriceResolverFactory
            .connect(deployer)
            .deploy(basicUnitPrice, true, 2, 2, priceCap, PriceFunction.CONSTANT, 2, 10);

        await expect(basicToken.connect(deployer).updatePriceResolver(balancePriceResolver.address))
            .not.to.be.reverted;
    });

    it('Assign exponential price resolver', async () => {
        const balancePriceResolverFactory = await ethers.getContractFactory('BalancePriceResolver');
        balancePriceResolver = await balancePriceResolverFactory
            .connect(deployer)
            .deploy(basicUnitPrice, true, 2, 2, priceCap, PriceFunction.EXP, 2, 10);

        await expect(basicToken.connect(deployer).updatePriceResolver(balancePriceResolver.address))
            .not.to.be.reverted;
    });
});
