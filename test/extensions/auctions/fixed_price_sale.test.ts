import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('FixedPriceSale tests', () => {
    const projectId = 1;
    const salePrice = ethers.utils.parseEther('1');
    const saleDuration = 60 * 60;
    const feeRate = 5_000_000; // 0.5%
    const feeDenominator = 1_000_000_000;
    const allowPublicSale = true;

    let deployer: SignerWithAddress;
    let tokenOwner: SignerWithAddress;
    let accounts: SignerWithAddress[];

    let directory;
    let feeReceiverTerminal;

    let token: any
    let fixedPriceSale: any;
    let splits: any[];

    let nextTokenId = 1;

    before('Initialize accounts', async () => {
        [deployer, tokenOwner, ...accounts] = await ethers.getSigners();
    });

    before('Setup JBX components', async () => {
        directory = await deployMockContract(deployer, jbDirectory.abi);
        feeReceiverTerminal = await deployMockContract(deployer, jbTerminal.abi);

        await feeReceiverTerminal.mock.addToBalanceOf.returns();
        await directory.mock.isTerminalOf.withArgs(projectId, feeReceiverTerminal.address).returns(true);
    });

    before('Initialize contracts', async () => {
        const fixedPriceSaleFactory = await ethers.getContractFactory('FixedPriceSale', { signer: deployer });

        fixedPriceSale = await fixedPriceSaleFactory.connect(deployer).deploy();
        await fixedPriceSale.deployed();
        fixedPriceSale.connect(deployer).initialize(projectId, feeReceiverTerminal.address, feeRate, allowPublicSale, deployer.address, directory.address)
    });

    before('Initialize aux state', async () => {
        const tokenFactory = await ethers.getContractFactory('MockERC721', deployer);
        token = await tokenFactory.connect(deployer).deploy();

        splits = [
            {
                preferClaimed: true,
                preferAddToBalance: true,
                percent: 500_000_000,
                projectId: 0,
                beneficiary: accounts[2].address,
                lockedUntil: 0,
                allocator: ethers.constants.AddressZero
            },
            {
                preferClaimed: true,
                preferAddToBalance: true,
                percent: 500_000_000,
                projectId: 0,
                beneficiary: accounts[3].address,
                lockedUntil: 0,
                allocator: ethers.constants.AddressZero
            }
        ];
    });

    it(`create() success`, async () => {
        const tokenId = nextTokenId++;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);
        await token.connect(tokenOwner).approve(fixedPriceSale.address, tokenId);

        await expect(
            fixedPriceSale
                .connect(tokenOwner)
                .create(token.address, tokenId, salePrice, saleDuration, [], '')
        ).to.emit(fixedPriceSale, 'CreateFixedPriceSale').withArgs(tokenOwner.address, token.address, tokenId, salePrice, anyValue, '');
    });

    it(`create() fail: sale already exists`, async () => {
        const tokenId = 1;

        await expect(
            fixedPriceSale
                .connect(tokenOwner)
                .create(token.address, tokenId, salePrice, saleDuration, [], '')
        ).to.be.revertedWith('SALE_EXISTS()');
    });

    it(`create() fail: invalid price`, async () => {
        const tokenId = nextTokenId++;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);
        await token.connect(tokenOwner).approve(fixedPriceSale.address, tokenId);

        await expect(
            fixedPriceSale
                .connect(tokenOwner)
                .create(token.address, 2, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', saleDuration, [], '')
        ).to.be.revertedWith('INVALID_PRICE()');
    });

    it(`create() fail: no public sales`, async () => {
        await fixedPriceSale.connect(deployer).setAllowPublicSales(false);

        const tokenId = 1;
        await expect(
            fixedPriceSale
                .connect(tokenOwner)
                .create(token.address, tokenId, salePrice, saleDuration, [], '')
        ).to.be.revertedWith('NOT_AUTHORIZED()');

        await fixedPriceSale.connect(deployer).setAllowPublicSales(true);
    });

    it(`create() fail: invalid duration`, async () => {
        const tokenId = 2;
        await expect(
            fixedPriceSale
                .connect(tokenOwner)
                .create(token.address, tokenId, salePrice, BigNumber.from('0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'), [], '')
        ).to.be.revertedWithCustomError(fixedPriceSale, 'INVALID_DURATION');
    });

    it(`takeOffer() success: sale`, async () => {
        const expectedFee = salePrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = salePrice.sub(expectedFee);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);

        const tokenId = nextTokenId++;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);
        await token.connect(tokenOwner).approve(fixedPriceSale.address, tokenId);
        await fixedPriceSale.connect(tokenOwner).create(token.address, tokenId, salePrice, saleDuration, [], '');

        let tx = await fixedPriceSale.connect(accounts[0]).takeOffer(token.address, tokenId, '', { value: salePrice });
        await expect(tx)
            .to.emit(fixedPriceSale, 'ConcludeFixedPriceSale')
            .withArgs(tokenOwner.address, accounts[0].address, token.address, tokenId, salePrice, '');

        await expect(fixedPriceSale.connect(accounts[3]).distributeProceeds(token.address, 999))
            .to.be.revertedWithCustomError(fixedPriceSale, 'INVALID_SALE');

        tx = await fixedPriceSale.connect(accounts[3]).distributeProceeds(token.address, tokenId);
        await expect(tx).to.changeEtherBalance(tokenOwner, expectedProceeds);

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance).to.be.greaterThan(initialBalance);
    });

    it(`takeOffer() success: split payments`, async () => {
        const tokenId = nextTokenId++;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);
        await token.connect(tokenOwner).approve(fixedPriceSale.address, tokenId);
        await fixedPriceSale.connect(tokenOwner).create(token.address, tokenId, salePrice, saleDuration, splits, '');

        const expectedFee = salePrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = salePrice.sub(expectedFee).div(2);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);

        let tx = await fixedPriceSale.connect(accounts[1]).takeOffer(token.address, tokenId, '', { value: salePrice });
        await expect(tx)
            .to.emit(fixedPriceSale, 'ConcludeFixedPriceSale')
            .withArgs(tokenOwner.address, accounts[1].address, token.address, tokenId, salePrice, '');

        tx = await fixedPriceSale.connect(accounts[0]).distributeProceeds(token.address, tokenId);
        await expect(tx).to.changeEtherBalances([tokenOwner, accounts[2], accounts[3]], [0, expectedProceeds, expectedProceeds]);

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance.sub(initialBalance)).to.equal(expectedFee);
    });

    it(`distributeProceeds() fail: sale in progress`, async () => {
        const tokenId = nextTokenId++;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);
        await token.connect(tokenOwner).approve(fixedPriceSale.address, tokenId);
        await fixedPriceSale.connect(tokenOwner).create(token.address, tokenId, salePrice, saleDuration, [], '');

        await expect(fixedPriceSale.connect(accounts[0]).distributeProceeds(token.address, tokenId))
            .to.be.revertedWithCustomError(fixedPriceSale, 'SALE_IN_PROGRESS');
    });

    it(`takeOffer() success: return token to seller`, async () => {
        const tokenId = nextTokenId++;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);
        await token.connect(tokenOwner).approve(fixedPriceSale.address, tokenId);
        await fixedPriceSale.connect(tokenOwner).create(token.address, tokenId, salePrice, saleDuration, [], '');

        await ethers.provider.send("evm_increaseTime", [saleDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        let tx = fixedPriceSale.connect(accounts[1]).distributeProceeds(token.address, tokenId);
        await expect(await tx)
            .to.emit(fixedPriceSale, 'ConcludeFixedPriceSale').withArgs(tokenOwner.address, ethers.constants.AddressZero, token.address, tokenId, 0, '');
    });

    it(`takeOffer() fail: sale ended`, async () => {
        const tokenId = nextTokenId++;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);
        await token.connect(tokenOwner).approve(fixedPriceSale.address, tokenId);
        await fixedPriceSale.connect(tokenOwner).create(token.address, tokenId, salePrice, saleDuration, [], '');

        await ethers.provider.send("evm_increaseTime", [saleDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        await expect(
            fixedPriceSale
                .connect(accounts[1])
                .takeOffer(token.address, tokenId, '', { value: salePrice })
        ).to.be.revertedWith('SALE_ENDED()');
    });

    it(`takeOffer() fail: invalid sale`, async () => {
        await expect(fixedPriceSale.connect(accounts[1]).takeOffer(token.address, nextTokenId + 1, '', { value: salePrice }))
            .to.be.revertedWith('INVALID_SALE()');
    });

    it(`distributeProceeds() success: transfer token`, async () => {
        const tokenId = nextTokenId++;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);
        await token.connect(tokenOwner).approve(fixedPriceSale.address, tokenId);
        await fixedPriceSale.connect(tokenOwner).create(token.address, tokenId, salePrice, saleDuration, [], '');

        await fixedPriceSale.connect(accounts[0]).takeOffer(token.address, tokenId, '', { value: salePrice });

        const expectedFee = salePrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = salePrice.sub(expectedFee);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);

        let tx = await fixedPriceSale.connect(accounts[3]).distributeProceeds(token.address, tokenId);
        await expect(tx).to.changeEtherBalance(tokenOwner, expectedProceeds);

        await expect(fixedPriceSale.connect(accounts[1]).takeOffer(token.address, tokenId, ''))
            .to.be.revertedWithCustomError(fixedPriceSale, 'INVALID_SALE');

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance).to.be.greaterThan(initialBalance);
    });

    it('update splits', async () => {
        const tokenId = nextTokenId++;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);
        await token.connect(tokenOwner).approve(fixedPriceSale.address, tokenId);
        await fixedPriceSale.connect(tokenOwner).create(token.address, tokenId, salePrice, saleDuration, [], '');

        await expect(fixedPriceSale.connect(accounts[0]).updateSaleSplits(token.address, tokenId, [])).to.be.revertedWithCustomError(fixedPriceSale, 'NOT_AUTHORIZED');
        await expect(fixedPriceSale.connect(accounts[0]).updateSaleSplits(token.address, tokenId + 10, [])).to.be.revertedWithCustomError(fixedPriceSale, 'INVALID_SALE');
        await fixedPriceSale.connect(tokenOwner).updateSaleSplits(token.address, tokenId, splits);
    });

    it(`currentPrice()`, async () => {
        const tokenId = nextTokenId++;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);
        await token.connect(tokenOwner).approve(fixedPriceSale.address, tokenId);
        await fixedPriceSale.connect(tokenOwner).create(token.address, tokenId, salePrice, saleDuration, [], '');

        expect(await fixedPriceSale.currentPrice(token.address, tokenId)).to.eq(salePrice);

        await ethers.provider.send("evm_setNextBlockTimestamp", [saleDuration + 60]);
        await ethers.provider.send("evm_mine", []);

        expect(await fixedPriceSale.currentPrice(token.address, tokenId)).to.eq(0);

        await expect(fixedPriceSale.currentPrice(token.address, 999))
            .to.be.revertedWithCustomError(fixedPriceSale, 'INVALID_SALE');
    });

    it(`setFeeRate() success`, async () => {
        await expect(
            fixedPriceSale
                .connect(deployer)
                .setFeeRate('10000000')
        ).to.not.be.reverted;
    });

    it(`setFeeRate() failure: fee rate too high`, async () => {
        await expect(
            fixedPriceSale
                .connect(deployer)
                .setFeeRate('1000000000')
        ).to.be.revertedWith('INVALID_FEERATE()');
    });

    it(`setFeeRate() failure: not admin`, async () => {
        await expect(
            fixedPriceSale
                .connect(accounts[0])
                .setFeeRate('10000000')
        ).to.be.reverted;
    });

    it(`setAllowPublicSales() success`, async () => {
        await expect(fixedPriceSale.connect(deployer).setAllowPublicSales(true))
            .to.not.be.reverted;
    });

    it(`setAllowPublicSales() failure: not admin`, async () => {
        await expect(fixedPriceSale.connect(accounts[0]).setAllowPublicSales(false))
            .to.be.reverted;
    });

    it(`setFeeReceiver() success`, async () => {
        await expect(
            fixedPriceSale
                .connect(deployer)
                .setFeeReceiver(accounts[0].address)
        ).to.not.be.reverted;
    });

    it(`setFeeReceiver() failure: `, async () => {
        await expect(
            fixedPriceSale
                .connect(accounts[0])
                .setFeeReceiver(accounts[0].address)
        ).to.be.reverted;
    });

    it(`addAuthorizedSeller() success`, async () => {
        await expect(
            fixedPriceSale
                .connect(deployer)
                .addAuthorizedSeller(accounts[0].address)
        ).to.not.be.reverted;
    });

    it(`addAuthorizedSeller() failure: `, async () => {
        await expect(
            fixedPriceSale
                .connect(accounts[0])
                .addAuthorizedSeller(accounts[0].address)
        ).to.be.reverted;
    });

    it(`removeAuthorizedSeller() success`, async () => {
        await expect(
            fixedPriceSale
                .connect(deployer)
                .removeAuthorizedSeller(deployer.address)
        ).to.not.be.reverted;
    });

    it(`removeAuthorizedSeller() failure: not admin`, async () => {
        await expect(
            fixedPriceSale
                .connect(accounts[0])
                .removeAuthorizedSeller(accounts[0].address)
        ).to.be.reverted;
    });
});
