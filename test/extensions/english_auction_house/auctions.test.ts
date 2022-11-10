import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber } from 'ethers';
import { deployMockContract } from '@ethereum-waffle/mock-contract';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('EnglishAuctionHouse tests', () => {
    const projectId = 1;
    const basePrice = ethers.utils.parseEther('1');
    const reservePrice = ethers.utils.parseEther('2');
    const tokenId = 1;
    const auctionDuration = 60 * 60;
    const feeRate = 5_000_000; // 0.5%
    const feeDenominator = 1_000_000_000;
    const allowPublicAuctions = true;

    async function setup() {
        let [deployer, tokenOwner, ...accounts] = await ethers.getSigners();

        const directory = await deployMockContract(deployer, jbDirectory.abi);
        const feeReceiverTerminal = await deployMockContract(deployer, jbTerminal.abi);

        await feeReceiverTerminal.mock.addToBalanceOf.returns();
        await directory.mock.isTerminalOf.withArgs(projectId, feeReceiverTerminal.address).returns(true);

        const englishAuctionHouseFactory = await ethers.getContractFactory('EnglishAuctionHouse', { signer: deployer });

        const englishAuctionHouse = await englishAuctionHouseFactory.connect(deployer).deploy();
        await englishAuctionHouse.deployed();
        englishAuctionHouse.connect(deployer).initialize(projectId, feeReceiverTerminal.address, feeRate, allowPublicAuctions, deployer.address, directory.address)

        const tokenFactory = await ethers.getContractFactory('MockERC721', deployer);
        const token = await tokenFactory.connect(deployer).deploy();
        await token.connect(deployer).mint(tokenOwner.address, tokenId);

        const splits = [
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

        return {
            deployer,
            accounts,
            tokenOwner,
            englishAuctionHouse,
            token,
            feeReceiverTerminal,
            splits
        };
    }

    async function create(token, englishAuctionHouse, tokenOwner) {
        await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);
        await englishAuctionHouse.connect(tokenOwner).create(token.address, tokenId, basePrice, reservePrice, auctionDuration, [], '');
    }

    it(`create() success`, async () => {
        const { englishAuctionHouse, token, tokenOwner } = await setup();

        await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);

        await expect(
            englishAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, basePrice, 0, auctionDuration, [], '')
        ).to.emit(englishAuctionHouse, 'CreateEnglishAuction').withArgs(tokenOwner.address, token.address, tokenId, basePrice, 0, anyValue, '');
    });

    it(`create() fail: not token owner`, async () => {
        const { accounts, englishAuctionHouse, token } = await setup();

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .create(token.address, tokenId, basePrice, 0, auctionDuration, [], '')
        ).to.be.revertedWith('ERC721: caller is not token owner or approved');
    });

    it(`create() fail: auction already exists`, async () => {
        const { englishAuctionHouse, token, tokenOwner } = await setup();

        await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);
        await englishAuctionHouse.connect(tokenOwner).create(token.address, tokenId, basePrice, 0, auctionDuration, [], '');

        await expect(
            englishAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, basePrice, 0, auctionDuration, [], '')
        ).to.be.revertedWith('AUCTION_EXISTS()');
    });

    it(`create() fail: invalid price`, async () => {
        const { englishAuctionHouse, token, tokenOwner } = await setup();

        await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);

        await expect(
            englishAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', 0, auctionDuration, [], '')
        ).to.be.revertedWith('INVALID_PRICE()');
    });

    it(`create() fail: invalid price`, async () => {
        const { englishAuctionHouse, token, tokenOwner } = await setup();

        await token.connect(tokenOwner).approve(englishAuctionHouse.address, 1);

        await expect(
            englishAuctionHouse
                .connect(tokenOwner)
                .create(token.address, 1, basePrice, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', auctionDuration, [], '')
        ).to.be.revertedWith('INVALID_PRICE()');
    });

    it(`create() fail: no public auctions`, async () => {
        const { deployer, englishAuctionHouse, token, tokenOwner } = await setup();

        await englishAuctionHouse.connect(deployer).setAllowPublicAuctions(false);

        await expect(
            englishAuctionHouse
                .connect(tokenOwner)
                .create(token.address, 1, basePrice, reservePrice, auctionDuration, [], '')
        ).to.be.revertedWith('NOT_AUTHORIZED()');
    });

    it(`create() fail: no public auctions`, async () => {
        const { deployer, englishAuctionHouse, token, tokenOwner } = await setup();

        await expect(
            englishAuctionHouse
                .connect(tokenOwner)
                .create(token.address, 1, basePrice, reservePrice, BigNumber.from('0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'), [], '')
        ).to.be.revertedWithCustomError(englishAuctionHouse, 'INVALID_DURATION');
    });


    it(`bid() success: initial`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: basePrice })
        ).to.emit(englishAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, tokenId, basePrice, '');
    });

    it(`bid() success: increase bid`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);
        await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: basePrice });

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: reservePrice })
        ).to.emit(englishAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, tokenId, reservePrice, '');

        expect(await englishAuctionHouse.timeLeft(token.address, tokenId)).to.be.greaterThan(0);
    });

    it(`bid() fail: invalid price`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: '10000' })
        ).to.be.revertedWith('INVALID_BID()');
    });

    it(`bid() fail: invalid price, below current`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);
        await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: reservePrice });

        await expect(
            englishAuctionHouse
                .connect(accounts[1])
                .bid(token.address, tokenId, '', { value: basePrice })
        ).to.be.revertedWith('INVALID_BID()');
    });

    it(`bid() fail: invalid price, at current`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);
        await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: reservePrice });

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: reservePrice })
        ).to.be.revertedWith('INVALID_BID()');
    });

    it(`bid() fail: invalid auction`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId + 1, '', { value: '10000' })
        ).to.be.revertedWith('INVALID_AUCTION()');

        expect(await englishAuctionHouse.timeLeft(token.address, tokenId)).to.be.revertedWithCustomError(englishAuctionHouse, 'INVALID_AUCTION');
    });

    it(`bid() fail: auction ended`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);
        await ethers.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: '10000' })
        ).to.be.revertedWith('AUCTION_ENDED()');

        expect(await englishAuctionHouse.timeLeft(token.address, tokenId)).to.equal(0);
    });

    it(`settle() success: sale`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner, feeReceiverTerminal } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);
        await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: reservePrice });

        await ethers.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        const expectedFee = reservePrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = reservePrice.sub(expectedFee);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);

        let tx = await englishAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, '');
        await expect(tx)
            .to.emit(englishAuctionHouse, 'ConcludeAuction')
            .withArgs(tokenOwner.address, accounts[0].address, token.address, tokenId, reservePrice, '');

        await expect(englishAuctionHouse.connect(accounts[3]).distributeProceeds(token.address, 999))
            .to.be.revertedWithCustomError(englishAuctionHouse, 'INVALID_AUCTION');

        tx = await englishAuctionHouse.connect(accounts[3]).distributeProceeds(token.address, tokenId);
        await expect(tx).to.changeEtherBalance(tokenOwner, expectedProceeds);

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance).to.be.greaterThan(initialBalance);
    });

    it(`settle() success: split payments`, async () => {
        const { accounts, englishAuctionHouse, splits, token, tokenOwner, feeReceiverTerminal } = await setup();

        await token.connect(tokenOwner).approve(englishAuctionHouse.address, tokenId);
        await englishAuctionHouse.connect(tokenOwner).create(token.address, tokenId, basePrice, reservePrice, auctionDuration, splits, '');
        await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: reservePrice });

        await ethers.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        const expectedFee = reservePrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = reservePrice.sub(expectedFee).div(2);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);

        let tx = await englishAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, '');
        await expect(tx)
            .to.emit(englishAuctionHouse, 'ConcludeAuction')
            .withArgs(tokenOwner.address, accounts[0].address, token.address, tokenId, reservePrice, '');

        tx = await englishAuctionHouse.connect(accounts[0]).distributeProceeds(token.address, tokenId);
        await expect(tx).to.changeEtherBalances([tokenOwner, accounts[2], accounts[3]], [0, expectedProceeds, expectedProceeds]);

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance.sub(initialBalance)).to.equal(expectedFee);
    });

    it(`settle()/distributeProceeds() fail: auction in progress/reserve not met`, async () => {
        const { accounts, englishAuctionHouse, splits, token, tokenOwner } = await setup();

        await token.connect(tokenOwner).approve(englishAuctionHouse.address, tokenId);
        await englishAuctionHouse.connect(tokenOwner).create(token.address, tokenId, basePrice, reservePrice, auctionDuration, splits, '');
        await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: basePrice });

        await expect(englishAuctionHouse.connect(accounts[0]).distributeProceeds(token.address, tokenId))
            .to.be.revertedWithCustomError(englishAuctionHouse, 'AUCTION_IN_PROGRESS');

        await ethers.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        let tx = await englishAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, '');
        await expect(tx).to.changeEtherBalances([accounts[0]], [basePrice]);

    });

    it(`settle() success: return token to seller`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);
        await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: basePrice });

        await ethers.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        let tx = englishAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, '');
        await expect(await tx)
            .to.emit(englishAuctionHouse, 'ConcludeAuction').withArgs(tokenOwner.address, ethers.constants.AddressZero, token.address, tokenId, 0, '');
        await expect(await tx).to.changeEtherBalance(accounts[0], basePrice);
    });

    it(`settle() fail: auction in progress`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);

        await ethers.provider.send("evm_increaseTime", [auctionDuration - 10000]);
        await ethers.provider.send("evm_mine", []);

        await expect(
            englishAuctionHouse
                .connect(accounts[1])
                .settle(token.address, tokenId, '')
        ).to.be.revertedWith('AUCTION_IN_PROGRESS()');
    });

    it(`settle() fail: invalid auction`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);

        await expect(
            englishAuctionHouse
                .connect(accounts[1])
                .settle(token.address, tokenId + 1, '')
        ).to.be.revertedWith('INVALID_AUCTION()');
    });

    it(`distributeProceeds() success: transfer token`, async () => {
        const { accounts, englishAuctionHouse, token, tokenOwner, feeReceiverTerminal } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);
        await englishAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: reservePrice });

        await ethers.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        const expectedFee = reservePrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = reservePrice.sub(expectedFee);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);

        let tx = await englishAuctionHouse.connect(accounts[3]).distributeProceeds(token.address, tokenId);
        await expect(tx).to.changeEtherBalance(tokenOwner, expectedProceeds);
        await expect(tx).to.emit(englishAuctionHouse, 'ConcludeAuction');

        await expect(englishAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, ''))
            .to.be.revertedWithCustomError(englishAuctionHouse, 'INVALID_AUCTION');

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance).to.be.greaterThan(initialBalance);
    });

    it('update splits', async () => {
        const { accounts, englishAuctionHouse, splits, token, tokenOwner } = await setup();

        await create(token, englishAuctionHouse, tokenOwner);

        await expect(englishAuctionHouse.connect(accounts[0]).updateAuctionSplits(token.address, tokenId, [])).to.be.revertedWithCustomError(englishAuctionHouse, 'NOT_AUTHORIZED');
        await expect(englishAuctionHouse.connect(accounts[0]).updateAuctionSplits(token.address, tokenId + 10, [])).to.be.revertedWithCustomError(englishAuctionHouse, 'INVALID_AUCTION');
        await englishAuctionHouse.connect(tokenOwner).updateAuctionSplits(token.address, tokenId, splits);
    });

    it(`currentPrice()`, async () => {
        const { accounts, englishAuctionHouse, splits, token, tokenOwner } = await setup();

        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + 60]);
        await ethers.provider.send("evm_mine", []);

        await create(token, englishAuctionHouse, tokenOwner);

        expect(await englishAuctionHouse.currentPrice(token.address, tokenId)).to.eq(0);

        await expect(englishAuctionHouse.currentPrice(token.address, 999))
            .to.be.revertedWithCustomError(englishAuctionHouse, 'INVALID_AUCTION');
    });

    it(`setFeeRate() success`, async () => {
        const { deployer, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(deployer)
                .setFeeRate('10000000')
        ).to.not.be.reverted;
    });

    it(`setFeeRate() failure: fee rate too high`, async () => {
        const { deployer, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(deployer)
                .setFeeRate('1000000000')
        ).to.be.revertedWith('INVALID_FEERATE()');
    });

    it(`setFeeRate() failure: not admin`, async () => {
        const { accounts, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .setFeeRate('10000000')
        ).to.be.reverted;
    });

    it(`setAllowPublicAuctions() success`, async () => {
        const { deployer, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(deployer)
                .setAllowPublicAuctions(true)
        ).to.not.be.reverted;
    });

    it(`setAllowPublicAuctions() failure: not admin`, async () => {
        const { accounts, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .setAllowPublicAuctions(false)
        ).to.be.reverted;
    });

    it(`setFeeReceiver() success`, async () => {
        const { accounts, deployer, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(deployer)
                .setFeeReceiver(accounts[0].address)
        ).to.not.be.reverted;
    });

    it(`setFeeReceiver() failure: `, async () => {
        const { accounts, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .setFeeReceiver(accounts[0].address)
        ).to.be.reverted;
    });

    it(`addAuthorizedSeller() success`, async () => {
        const { accounts, deployer, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(deployer)
                .addAuthorizedSeller(accounts[0].address)
        ).to.not.be.reverted;
    });

    it(`addAuthorizedSeller() failure: `, async () => {
        const { accounts, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .addAuthorizedSeller(accounts[0].address)
        ).to.be.reverted;
    });

    it(`removeAuthorizedSeller() success`, async () => {
        const { accounts, deployer, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(deployer)
                .removeAuthorizedSeller(deployer.address)
        ).to.not.be.reverted;
    });

    it(`removeAuthorizedSeller() failure: not admin`, async () => {
        const { accounts, englishAuctionHouse } = await setup();

        await expect(
            englishAuctionHouse
                .connect(accounts[0])
                .removeAuthorizedSeller(accounts[0].address)
        ).to.be.reverted;
    });
});
