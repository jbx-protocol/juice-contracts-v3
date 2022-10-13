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

describe('SupplyPriceResolver tests', () => {
    const basicProjectId = 99;
    const basicUnitPrice = ethers.utils.parseEther('0.001');
    const priceCap = ethers.utils.parseEther('0.01');

    let deployer: SignerWithAddress;
    let accounts: SignerWithAddress[];

    let directory;
    let basicToken: any;
    let supplyPriceResolver: any;

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
        const basicMaxSupply = 100;
        const basicMintAllowance = 10;
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

    it('Assign linear price resolver', async () => {
        const supplyPriceResolverFactory = await ethers.getContractFactory('SupplyPriceResolver');
        supplyPriceResolver = await supplyPriceResolverFactory
            .connect(deployer)
            .deploy(basicUnitPrice, 2, 2, priceCap, PriceFunction.LINEAR);

        await expect(basicToken.connect(accounts[0]).updatePriceResolver(supplyPriceResolver.address))
            .to.be.reverted;
        await expect(basicToken.connect(deployer).updatePriceResolver(supplyPriceResolver.address))
            .not.to.be.reverted;
    });

    it('Get price for 1st token', async () => {
        expect(await supplyPriceResolver.getPrice(basicToken.address, ethers.constants.AddressZero, 0))
            .to.equal(basicUnitPrice);
    });

    it('Get 2nd tier price', async () => {
        await basicToken.connect(accounts[0])['mint()']({value: basicUnitPrice});
        await basicToken.connect(accounts[0])['mint()']({value: basicUnitPrice});

        expect(await supplyPriceResolver.getPrice(basicToken.address, ethers.constants.AddressZero, 0))
            .to.equal(basicUnitPrice.mul(2));
    });

    it('Assign constant price resolver', async () => {
        const supplyPriceResolverFactory = await ethers.getContractFactory('SupplyPriceResolver');
        const oneXsupplyPriceResolver = await supplyPriceResolverFactory
            .connect(deployer)
            .deploy(basicUnitPrice, 1, 2, priceCap, PriceFunction.CONSTANT);

        const tenXsupplyPriceResolver = await supplyPriceResolverFactory
            .connect(deployer)
            .deploy(basicUnitPrice, 10, 2, priceCap, PriceFunction.CONSTANT);

        const onePrice = await oneXsupplyPriceResolver.getPrice(basicToken.address, ethers.constants.AddressZero, 0);
        const tenPrice = await tenXsupplyPriceResolver.getPrice(basicToken.address, ethers.constants.AddressZero, 0);
        expect(onePrice).to.equal(tenPrice);
    });

    it('Assign exponential price resolver', async () => {
        const supplyPriceResolverFactory = await ethers.getContractFactory('SupplyPriceResolver');
        supplyPriceResolver = await supplyPriceResolverFactory
            .connect(deployer)
            .deploy(basicUnitPrice, 2, 2, priceCap, PriceFunction.EXP);

        await expect(basicToken.connect(deployer).updatePriceResolver(supplyPriceResolver.address))
            .not.to.be.reverted;
    });

    it('Mint 2nd EXP tier', async () => {
        const multiplier = 2;
        const tierSize = 2;
        let currentSupply = (await basicToken.totalSupply() as BigNumber).toNumber();
        let expectedPrice = basicUnitPrice.mul(multiplier ** Math.floor(currentSupply / tierSize));

        await expect(basicToken.connect(accounts[0])['mint()']({value: expectedPrice}))
            .not.to.be.reverted;

        expectedPrice = basicUnitPrice.mul(multiplier ** Math.floor(currentSupply / tierSize));

        currentSupply = (await basicToken.totalSupply() as BigNumber).toNumber();
        await expect(basicToken.connect(accounts[0])['mint()']({value: expectedPrice}))
            .not.to.be.reverted;
    });

    it('Mint at price cap', async () => {
        let expectedPrice = (await supplyPriceResolver.getPrice(basicToken.address, ethers.constants.AddressZero, 0)) as BigNumber;
        while(expectedPrice.lt(priceCap)){
            expectedPrice = await supplyPriceResolver.getPriceWithParams(basicToken.address, ethers.constants.AddressZero, 0, '0x00');
            basicToken.connect(accounts[0])['mint()']({value: expectedPrice});
        }

        await expect(basicToken.connect(accounts[0])['mint()']({value: priceCap}))
            .not.to.be.reverted;
    });
});
