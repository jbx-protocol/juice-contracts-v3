import { expect } from 'chai';
import { ethers } from 'hardhat';
import { deployMockContract } from '@ethereum-waffle/mock-contract';

import jbDirectory from '../../../artifacts/contracts/JBDirectory.sol/JBDirectory.json';
import jbTerminal from '../../../artifacts/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol/JBPayoutRedemptionPaymentTerminal.json';

describe('DutchAuctionHouse tests', () => {
    const projectId = 1;
    const startPrice = ethers.utils.parseEther('2');
    const endPrice = ethers.utils.parseEther('1');
    const tokenId = 1;
    const auctionDuration = 60 * 60;
    const feeRate = 5_000_000; // 0.5%
    const pricingPeriodDuration = 5 * 60; // seconds
    const feeDenominator = 1_000_000_000;
    const allowPublicAuctions = true;

    async function setup() {
        let [deployer, tokenOwner, ...accounts] = await ethers.getSigners();

        const directory = await deployMockContract(deployer, jbDirectory.abi);
        const feeReceiverTerminal = await deployMockContract(deployer, jbTerminal.abi);

        await feeReceiverTerminal.mock.addToBalanceOf.returns();
        await directory.mock.isTerminalOf.withArgs(projectId, feeReceiverTerminal.address).returns(true);

        const dutchAuctionHouseFactory = await ethers.getContractFactory('DutchAuctionHouse', {
            signer: deployer
        });
        const dutchAuctionHouse = await dutchAuctionHouseFactory
            .connect(deployer)
            .deploy(projectId, feeReceiverTerminal.address, feeRate, allowPublicAuctions, pricingPeriodDuration, deployer.address, directory.address);

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
            dutchAuctionHouse,
            token,
            feeReceiverTerminal,
            splits
        };
    }

    async function create(token, dutchAuctionHouse, tokenOwner) {
        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, tokenId);
        await dutchAuctionHouse.connect(tokenOwner).create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '');
    }

    it(`create() success`, async () => {
        const { dutchAuctionHouse, token, tokenOwner } = await setup();

        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, tokenId);

        await expect(
            dutchAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
        ).to.emit(dutchAuctionHouse, 'CreateDutchAuction').withArgs(tokenOwner.address, token.address, tokenId, startPrice, '');
    });

    it(`create() fail: not token owner`, async () => {
        const { accounts, dutchAuctionHouse, token } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
        ).to.be.revertedWith('ERC721: caller is not token owner nor approved');
    });

    it(`create() fail: auction already exists`, async () => {
        const { dutchAuctionHouse, token, tokenOwner } = await setup();

        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, 1);
        await dutchAuctionHouse.connect(tokenOwner).create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '');

        await expect(
            dutchAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
        ).to.be.revertedWith('AUCTION_EXISTS()');
    });

    it(`create() fail: invalid price`, async () => {
        const { dutchAuctionHouse, token, tokenOwner } = await setup();

        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, 1);

        await expect(
            dutchAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', endPrice, auctionDuration, [], '')
        ).to.be.revertedWith('INVALID_PRICE()');
    });

    it(`create() fail: invalid price`, async () => {
        const { dutchAuctionHouse, token, tokenOwner } = await setup();

        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, 1);

        await expect(
            dutchAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, startPrice, '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF', auctionDuration, [], '')
        ).to.be.revertedWith('INVALID_PRICE()');
    });

    it(`create() fail: no public auctions`, async () => {
        const { deployer, dutchAuctionHouse, token, tokenOwner } = await setup();

        await dutchAuctionHouse.connect(deployer).setAllowPublicAuctions(false);

        await expect(
            dutchAuctionHouse
                .connect(tokenOwner)
                .create(token.address, tokenId, startPrice, endPrice, auctionDuration, [], '')
        ).to.be.revertedWith('NOT_AUTHORIZED()');
    });

    it(`bid() success: initial`, async () => {
        const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

        await create(token, dutchAuctionHouse, tokenOwner);

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: startPrice })
        ).to.emit(dutchAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, tokenId, startPrice, '');
    });

    it(`bid() success: increase bid`, async () => {
        const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

        await create(token, dutchAuctionHouse, tokenOwner);
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: endPrice });

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: startPrice })
        ).to.emit(dutchAuctionHouse, 'PlaceBid').withArgs(accounts[0].address, token.address, tokenId, startPrice, '');
    });

    it(`bid() fail: invalid price`, async () => {
        const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

        await create(token, dutchAuctionHouse, tokenOwner);

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: '10000' })
        ).to.be.revertedWith('INVALID_BID()');
    });

    it(`bid() fail: invalid price, below current bid`, async () => {
        const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

        await create(token, dutchAuctionHouse, tokenOwner);
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: startPrice });

        await expect(
            dutchAuctionHouse
                .connect(accounts[1])
                .bid(token.address, tokenId, '', { value: endPrice })
        ).to.be.revertedWith('INVALID_BID()');
    });

    it(`bid() fail: invalid price, at current`, async () => {
        const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

        await create(token, dutchAuctionHouse, tokenOwner);
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: endPrice });

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: endPrice })
        ).to.be.revertedWith('INVALID_BID()');
    });

    it(`bid() fail: invalid auction`, async () => {
        const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

        await create(token, dutchAuctionHouse, tokenOwner);

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId + 1, '', { value: '10000' })
        ).to.be.revertedWith('INVALID_AUCTION()');
    });

    it(`bid() fail: auction ended`, async () => {
        const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await create(token, dutchAuctionHouse, tokenOwner);

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + auctionDuration + 120]);
        await ethers.provider.send("evm_mine", []);

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .bid(token.address, tokenId, '', { value: startPrice })
        ).to.be.revertedWith('AUCTION_ENDED()');
    });

    it(`settle() success: sale`, async () => {
        const { accounts, dutchAuctionHouse, feeReceiverTerminal, token, tokenOwner } = await setup();

        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await create(token, dutchAuctionHouse, tokenOwner);
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: startPrice });

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration * 2 + 120]);
        await ethers.provider.send("evm_mine", []);

        const expectedFee = startPrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = startPrice.sub(expectedFee);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        const tx = dutchAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, '');

        await expect(tx)
            .to.emit(dutchAuctionHouse, 'ConcludeAuction')
            .withArgs(tokenOwner.address, accounts[0].address, token.address, tokenId, startPrice, '');

        await expect(await tx)
            .to.changeEtherBalance(tokenOwner, expectedProceeds);

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance).to.be.greaterThan(initialBalance);
    });

    it(`settle() success: split payments`, async () => {
        const { accounts, dutchAuctionHouse, splits, token, tokenOwner, feeReceiverTerminal } = await setup();

        await token.connect(tokenOwner).approve(dutchAuctionHouse.address, tokenId);
        await dutchAuctionHouse.connect(tokenOwner).create(token.address, tokenId, startPrice, endPrice, auctionDuration, splits, '');
        await dutchAuctionHouse.connect(accounts[0]).bid(token.address, tokenId, '', { value: startPrice });

        await ethers.provider.send("evm_increaseTime", [auctionDuration + 1]);
        await ethers.provider.send("evm_mine", []);

        const expectedFee = startPrice.mul(feeRate).div(feeDenominator);
        const expectedProceeds = startPrice.sub(expectedFee).div(2);

        const initialBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        const tx = dutchAuctionHouse.connect(accounts[1]).settle(token.address, tokenId, '');

        await expect(tx)
            .to.emit(dutchAuctionHouse, 'ConcludeAuction')
            .withArgs(tokenOwner.address, accounts[0].address, token.address, tokenId, startPrice, '');
        await expect(await tx)
            .to.changeEtherBalances([tokenOwner, accounts[2], accounts[3]], [0, expectedProceeds, expectedProceeds]);

        const endingBalance = await ethers.provider.getBalance(feeReceiverTerminal.address);
        expect(endingBalance.sub(initialBalance)).to.equal(expectedFee);
    });

    it(`settle() success: return`, async () => {
        const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await create(token, dutchAuctionHouse, tokenOwner);

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + auctionDuration + 120]);
        await ethers.provider.send("evm_mine", []);

        await expect(
            dutchAuctionHouse
                .connect(accounts[1])
                .settle(token.address, tokenId, '')
        ).to.emit(dutchAuctionHouse, 'ConcludeAuction').withArgs(tokenOwner.address, ethers.constants.AddressZero, token.address, tokenId, 0, '');
    });

    it(`settle() fail: invalid auction`, async () => {
        const { accounts, dutchAuctionHouse, token, tokenOwner } = await setup();

        await create(token, dutchAuctionHouse, tokenOwner);

        await expect(
            dutchAuctionHouse
                .connect(accounts[1])
                .settle(token.address, tokenId + 1, '')
        ).to.be.revertedWith('INVALID_AUCTION()');
    });

    it(`currentPrice()`, async () => {
        const { dutchAuctionHouse, token, tokenOwner } = await setup();

        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + 60]);
        await ethers.provider.send("evm_mine", []);

        await create(token, dutchAuctionHouse, tokenOwner);

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration - 10]);
        await ethers.provider.send("evm_mine", []);
        expect(await dutchAuctionHouse.currentPrice(token.address, tokenId)).to.eq(startPrice);

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration + 65]);
        await ethers.provider.send("evm_mine", []);
        expect(await dutchAuctionHouse.currentPrice(token.address, tokenId)).to.lt(startPrice);
    });

    it(`currentPrice() fail: invalid auction`, async () => {
        const { dutchAuctionHouse, token, tokenOwner } = await setup();

        const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + 60]);
        await ethers.provider.send("evm_mine", []);

        await create(token, dutchAuctionHouse, tokenOwner);

        await ethers.provider.send("evm_setNextBlockTimestamp", [referenceTime + pricingPeriodDuration - 10]);
        await ethers.provider.send("evm_mine", []);
        await expect(dutchAuctionHouse.currentPrice(token.address, tokenId + 1)).to.be.revertedWith('INVALID_AUCTION()');
    });

    it(`setFeeRate() success`, async () => {
        const { deployer, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .setFeeRate('10000000')
        ).to.not.be.reverted;
    });

    it(`setFeeRate() failure: fee rate too high`, async () => {
        const { deployer, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .setFeeRate('1000000000')
        ).to.be.revertedWith('INVALID_FEERATE()');
    });

    it(`setFeeRate() failure: not admin`, async () => {
        const { accounts, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .setFeeRate('10000000')
        ).to.be.reverted;
    });

    it(`setAllowPublicAuctions() success`, async () => {
        const { deployer, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .setAllowPublicAuctions(true)
        ).to.not.be.reverted;
    });

    it(`setAllowPublicAuctions() failure: not admin`, async () => {
        const { accounts, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .setAllowPublicAuctions(false)
        ).to.be.reverted;
    });

    it(`setFeeReceiver() success`, async () => {
        const { accounts, deployer, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .setFeeReceiver(accounts[0].address)
        ).to.not.be.reverted;
    });

    it(`setFeeReceiver() failure: `, async () => {
        const { accounts, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .setFeeReceiver(accounts[0].address)
        ).to.be.reverted;
    });

    it(`addAuthorizedSeller() success`, async () => {
        const { accounts, deployer, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .addAuthorizedSeller(accounts[0].address)
        ).to.not.be.reverted;
    });

    it(`addAuthorizedSeller() failure: `, async () => {
        const { accounts, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .addAuthorizedSeller(accounts[0].address)
        ).to.be.reverted;
    });

    it(`removeAuthorizedSeller() success`, async () => {
        const { accounts, deployer, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(deployer)
                .removeAuthorizedSeller(deployer.address)
        ).to.not.be.reverted;
    });

    it(`removeAuthorizedSeller() failure: not admin`, async () => {
        const { accounts, dutchAuctionHouse } = await setup();

        await expect(
            dutchAuctionHouse
                .connect(accounts[0])
                .removeAuthorizedSeller(accounts[0].address)
        ).to.be.reverted;
    });
});
