import { expect } from 'chai';
import { ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('DutchAuctionHouse tests', () => {
    const projectId = 2;
    const startPrice = ethers.utils.parseEther('2');
    const endPrice = ethers.utils.parseEther('1');
    let tokenId = 1;
    const auctionDuration = 100 * 60;
    const feeRate = 5_000_000; // 0.5%
    const pricingPeriodDuration = 5 * 60; // seconds
    const feeDenominator = 1_000_000_000;

    let deployer: SignerWithAddress
    let tokenOwner: SignerWithAddress
    let accounts: SignerWithAddress[];
    let dutchAuctionHouse: any;
    let token: any;
    let feeReceiverTerminal: any;
    let splits: any[];
    let partialSplits: any[];

    before(async () => {
        const allowPublicAuctions = true;

        [deployer, tokenOwner, ...accounts] = await ethers.getSigners();

        feeReceiverTerminal = await deployMockContract(deployer, jbTerminal.abi);
        await feeReceiverTerminal.mock.addToBalanceOf.returns();

        const directory = await deployMockContract(deployer, jbDirectory.abi);
        await directory.mock.isTerminalOf.withArgs(projectId, feeReceiverTerminal.address).returns(true);

        const dutchAuctionHouseFactory = await ethers.getContractFactory('DutchAuctionHouse', {
            signer: deployer
        });
        dutchAuctionHouse = await dutchAuctionHouseFactory
            .connect(deployer)
            .deploy();
        await dutchAuctionHouse.deployed();
        await dutchAuctionHouse.connect(deployer).initialize(projectId, feeReceiverTerminal.address, feeRate, allowPublicAuctions, pricingPeriodDuration, deployer.address, directory.address);

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

        partialSplits = [
            {
                preferClaimed: true,
                preferAddToBalance: true,
                percent: 100_000_000,
                projectId: 0,
                beneficiary: accounts[2].address,
                lockedUntil: 0,
                allocator: ethers.constants.AddressZero
            },
            {
                preferClaimed: true,
                preferAddToBalance: true,
                percent: 200_000_000,
                projectId: 0,
                beneficiary: accounts[3].address,
                lockedUntil: 0,
                allocator: ethers.constants.AddressZero
            }
        ];
    });

    async function mint(owner = tokenOwner) {
        ++tokenId;
        await token.connect(deployer).mint(owner.address, tokenId);
    }

    async function mintCreate(owner = tokenOwner) {
        await mint(owner);
        await token.connect(owner).approve(dutchAuctionHouse.address, tokenId);
        await dutchAuctionHouse.connect(owner).create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '');
    }

    it(`create() without splits`, async () => {
        await mint();
        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, tokenId);

        await expect(
            dutchAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
        ).to.emit(dutchAuctionHouse, 'CreateDutchAuction').withArgs(tokenOwner.address, token.address, tokenId, startPrice, endPrice, anyValue, '');
    });

    it(`create() fail: not token owner`, async () => {
        ++tokenId;
        await token.connect(deployer).mint(tokenOwner.address, tokenId);

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
        ).to.be.revertedWith('ERC721: caller is not token owner or approved');
    });

    it(`create() fail: auction already exists`, async () => {
        await mintCreate();

        await expect(
            dutchAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
        ).to.be.revertedWith('AUCTION_EXISTS()');
    });

    it(`create() fail: invalid price`, async () => {
        await mint();
        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, tokenId);

        await expect(
            dutchAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', endPrice, auctionDuration, [], '')
        ).to.be.revertedWith('INVALID_PRICE()');
    });

    it(`create() fail: invalid price`, async () => {
        await mint();
        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, tokenId);

        await expect(
            dutchAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, startPrice, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', auctionDuration, [], '')
        ).to.be.revertedWith('INVALID_PRICE()');
    });

    it(`create() fail: no public auctions`, async () => {
        await dutchAuctionHouse.connect(deployer).setAllowPublicAuctions(false);

        await expect(
            dutchAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
        ).to.be.revertedWith('NOT_AUTHORIZED()');

        await dutchAuctionHouse.connect(deployer).setAllowPublicAuctions(true);
    });

    it(`bid() success: initial`, async () => {
        await mintCreate();

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: startPrice })
        ).to.emit(dutchAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, tokenId, startPrice, '');
    });

    it(`bid() success: increase bid`, async () => {
        await mintCreate();
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: endPrice });

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: startPrice })
        ).to.emit(dutchAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, tokenId, startPrice, '');

        expect(await dutchAuctionHouse.timeLeft(token.address, tokenId)).to.be.greaterThan(0);
    });

    it(`bid() fail: invalid price`, async () => {
        await mintCreate();

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: '10000' })
        ).to.be.revertedWith('INVALID_BID()');
    });

    it(`bid() fail: invalid price, below current bid`, async () => {
        await mintCreate();
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: startPrice });

        await expect(
            dutchAuctionHouse
                .connect(accounts[1])
                .bid(token.address, tokenId, '', { value: endPrice })
        ).to.be.revertedWith('INVALID_BID()');
    });

    it(`bid() fail: invalid price, at current`, async () => {
        await mintCreate();
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: endPrice });

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: endPrice })
        ).to.be.revertedWith('INVALID_BID()');
    });

    it(`bid() fail: invalid auction`, async () => {
        await mintCreate();

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId + 1, '', { value: '10000' })
        ).to.be.revertedWith('INVALID_AUCTION()');

        expect(await dutchAuctionHouse.timeLeft(token.address, tokenId)).to.be.revertedWithCustomError(dutchAuctionHouse, 'INVALID_AUCTION');
    });

    it(`bid() fail: auction ended`, async () => {
        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await mintCreate();

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + auctionDuration + 10]);
        await ethers.provider.send("evm_mine", []);

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: startPrice })
        ).to.be.revertedWith('AUCTION_ENDED()');

        expect(await dutchAuctionHouse.timeLeft(token.address, tokenId)).to.equal(0);
    });

    it(`settle()/distributeProceeds() success: sale`, async () => {
        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await mintCreate();
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: startPrice });

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration * 2 + 10]);
        await ethers.provider.send("evm_mine", []);

        const expectedFee = startPrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = startPrice.sub(expectedFee);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        let tx = dutchAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, '');

        await expect(tx)
            .to.emit(dutchAuctionHouse, 'ConcludeAuction')
            .withArgs(tokenOwner.address, accounts[0].address, token.address, tokenId, startPrice, '');

        tx = dutchAuctionHouse.connect(accounts[1]).distributeProceeds(token.address, tokenId);
        await expect(await tx)
            .to.changeEtherBalance(tokenOwner, expectedProceeds);

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance).to.be.greaterThan(initialBalance);
    });

    it(`distributeProceeds() success: sale`, async () => {
        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await mintCreate();
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: startPrice });

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration * 2 + 10]);
        await ethers.provider.send("evm_mine", []);

        const expectedFee = startPrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = startPrice.sub(expectedFee);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);

        let tx = dutchAuctionHouse.connect(accounts[1]).distributeProceeds(token.address, tokenId);
        await expect(await tx)
            .to.changeEtherBalance(tokenOwner, expectedProceeds);

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance).to.be.greaterThan(initialBalance);
        expect(await token.ownerOf(tokenId)).to.equal(accounts[0].address);
    });

    it(`distributeProceeds() fail: invalid price`, async () => {
        await mintCreate();
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: endPrice });

        expect(dutchAuctionHouse.connect(accounts[1]).distributeProceeds(token.address, tokenId)).to.be.revertedWithCustomError(dutchAuctionHouse, 'INVALID_PRICE');
    });

    it(`settle() success: split payments`, async () => {
        await mint();
        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, tokenId);
        await dutchAuctionHouse.connect(tokenOwner).create(token.address, tokenId, startPrice, endPrice, auctionDuration, splits, '');

        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: startPrice });

        await ethers.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        const expectedFee = startPrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = startPrice.sub(expectedFee).div(2);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        let tx = dutchAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, '');
        await expect(tx)
            .to.emit(dutchAuctionHouse, 'ConcludeAuction')
            .withArgs(tokenOwner.address, accounts[0].address, token.address, tokenId, startPrice, '');

        tx = dutchAuctionHouse.connect(accounts[1]).distributeProceeds(token.address, tokenId);
        await expect(await tx)
            .to.changeEtherBalances([tokenOwner, accounts[2], accounts[3]], [0, expectedProceeds, expectedProceeds]);

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance.sub(initialBalance)).to.equal(expectedFee);
    });

    it(`settle() success: partial split payments`, async () => {
        await mint();
        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, tokenId);
        await dutchAuctionHouse.connect(tokenOwner).create(token.address, tokenId, startPrice, endPrice, auctionDuration, partialSplits, '');

        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: startPrice });

        await ethers.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        const expectedFee = startPrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = startPrice.sub(expectedFee).div(10);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        let tx = dutchAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, '');
        await expect(tx)
            .to.emit(dutchAuctionHouse, 'ConcludeAuction')
            .withArgs(tokenOwner.address, accounts[0].address, token.address, tokenId, startPrice, '');

        tx = dutchAuctionHouse.connect(accounts[1]).distributeProceeds(token.address, tokenId);
        await expect(await tx)
            .to.changeEtherBalances([tokenOwner, accounts[2], accounts[3]], [expectedProceeds.mul(7), expectedProceeds, expectedProceeds.mul(2)]);

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance.sub(initialBalance)).to.equal(expectedFee);
    });

    it(`settle() success: return token`, async () => {
        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await mintCreate();

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + auctionDuration + 120]);
        await ethers.provider.send("evm_mine", []);

        await expect(
            dutchAuctionHouse
                .connect(accounts[1])
                .settle(token.address, tokenId, '')
        ).to.emit(dutchAuctionHouse, 'ConcludeAuction').withArgs(tokenOwner.address, ethers.constants.AddressZero, token.address, tokenId, 0, '');
    });

    it(`settle() fail: invalid auction`, async () => {
        await mintCreate();

        await expect(
            dutchAuctionHouse
                .connect(accounts[1])
                .settle(token.address, tokenId + 1, '')
        ).to.be.revertedWith('INVALID_AUCTION()');
    });

    it('update splits', async () => {
        await mintCreate();

        await expect(dutchAuctionHouse.connect(accounts[0]).updateAuctionSplits(token.address, tokenId, [])).to.be.revertedWithCustomError(dutchAuctionHouse, 'NOT_AUTHORIZED');
        await expect(dutchAuctionHouse.connect(accounts[0]).updateAuctionSplits(token.address, tokenId + 10, [])).to.be.revertedWithCustomError(dutchAuctionHouse, 'INVALID_AUCTION');
        await dutchAuctionHouse.connect(tokenOwner).updateAuctionSplits(token.address, tokenId, splits);
    });

    it(`currentPrice()`, async () => {
        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + 60]);
        await ethers.provider.send("evm_mine", []);

        await mintCreate();

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration - 10]);
        await ethers.provider.send("evm_mine", []);
        expect(await dutchAuctionHouse.currentPrice(token.address, tokenId)).to.eq(startPrice);

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration + 65]);
        await ethers.provider.send("evm_mine", []);
        expect(await dutchAuctionHouse.currentPrice(token.address, tokenId)).to.lt(startPrice);
    });

    it(`currentPrice() fail: invalid auction`, async () => {
        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + 60]);
        await ethers.provider.send("evm_mine", []);

        await mintCreate();

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration - 10]);
        await ethers.provider.send("evm_mine", []);
        await expect(dutchAuctionHouse.currentPrice(token.address, tokenId + 1)).to.be.revertedWith('INVALID_AUCTION()');
    });

    it(`setFeeRate() success`, async () => {
        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .setFeeRate('10000000')
        ).to.not.be.reverted;
    });

    it(`setFeeRate() failure: fee rate too high`, async () => {
        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .setFeeRate('1000000000')
        ).to.be.revertedWith('INVALID_FEERATE()');
    });

    it(`setFeeRate() failure: not admin`, async () => {
        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .setFeeRate('10000000')
        ).to.be.reverted;
    });

    it(`setAllowPublicAuctions() success`, async () => {
        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .setAllowPublicAuctions(true)
        ).to.not.be.reverted;
    });

    it(`setAllowPublicAuctions() failure: not admin`, async () => {
        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .setAllowPublicAuctions(false)
        ).to.be.reverted;
    });

    it(`setFeeReceiver() success`, async () => {
        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .setFeeReceiver(accounts[0].address)
        ).to.not.be.reverted;
    });

    it(`setFeeReceiver() failure: `, async () => {
        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .setFeeReceiver(accounts[0].address)
        ).to.be.reverted;
    });

    it(`addAuthorizedSeller() success`, async () => {
        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .addAuthorizedSeller(accounts[0].address)
        ).to.not.be.reverted;
    });

    it(`addAuthorizedSeller() failure: `, async () => {
        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .addAuthorizedSeller(accounts[0].address)
        ).to.be.reverted;
    });

    it(`removeAuthorizedSeller() success`, async () => {
        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .removeAuthorizedSeller(deployer.address)
        ).to.not.be.reverted;
    });

    it(`removeAuthorizedSeller() failure: not admin`, async () => {
        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .removeAuthorizedSeller(accounts[0].address)
        ).to.be.reverted;
    });
});
