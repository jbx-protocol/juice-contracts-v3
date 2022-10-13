import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('Vesting Tests', () => {
    let deployer;
    let accounts;
    let mockToken;
    let vesting;

    before(async () => {
        [deployer, ...accounts] = await ethers.getSigners();

        const vestingFactory = await ethers.getContractFactory('VestingPlanManager');
        vesting = await vestingFactory.connect(deployer).deploy();
        await vesting.deployed();

        const tokenFactory = await ethers.getContractFactory('MockERC20', deployer);
        mockToken = await tokenFactory.connect(deployer).deploy();
        await mockToken.connect(deployer).mint(deployer.address, 2_000_000_000);
    });

    it('Fail to fund', async () => {
        const vestingPeriodSeconds = 60 * 60 * 1;
        const periodicGrant = 100;
        const periods = 10;

        await expect(vesting.connect(deployer).create(
            accounts[0].address,
            mockToken.address,
            periodicGrant,
            0,
            vestingPeriodSeconds,
            periods,
            'Simple Vest'
        )).to.reverted;
    });

    it('Simple Path', async () => {
        const headLevel = await ethers.provider.getBlockNumber();
        const headBlock = await ethers.provider.getBlock(headLevel);

        const vestingPeriodSeconds = 60 * 60 * 1;
        const periodicGrant = 100;
        const periods = 10;
        const totalGrant = periodicGrant * periods;
        const cliffSeconds = headBlock.timestamp + vestingPeriodSeconds;

        const planId = getPlanId(accounts[0].address, deployer.address, mockToken.address, periodicGrant, cliffSeconds, vestingPeriodSeconds, periods);

        const initialSponsorBalance = await mockToken.balanceOf(deployer.address);

        await expect(vesting.connect(deployer).create(
            accounts[0].address,
            mockToken.address,
            0,
            cliffSeconds,
            vestingPeriodSeconds,
            periods,
            'Simple Vest'
        )).to.be.revertedWithCustomError(vesting, 'INVALID_CONFIGURATION');

        mockToken.connect(deployer).approve(vesting.address, '1000');
        await expect(vesting.connect(deployer).create(
            accounts[0].address,
            mockToken.address,
            periodicGrant,
            cliffSeconds,
            vestingPeriodSeconds,
            periods,
            'Simple Vest'
        )).to.emit(vesting, 'CreatePlan')
            .withArgs(accounts[0].address, deployer.address, mockToken.address, periodicGrant, cliffSeconds, vestingPeriodSeconds, 10, 'Simple Vest', planId);

        await expect(vesting.connect(deployer).create(
            accounts[0].address,
            mockToken.address,
            periodicGrant,
            cliffSeconds,
            vestingPeriodSeconds,
            periods,
            'Simple Vest'
        )).to.be.revertedWith('DUPLICATE_CONFIGURATION()');

        await expect(vesting.connect(accounts[1]).terminate(planId)).to.be.revertedWithCustomError(vesting, 'UNAUTHORIZED');

        const updatedSponsorBalance = await mockToken.balanceOf(deployer.address);

        expect(initialSponsorBalance - updatedSponsorBalance).to.equal(totalGrant);

        await ethers.provider.send('evm_increaseTime', [60 * 10]);
        await ethers.provider.send('evm_mine', []);

        await expect(vesting.connect(accounts[1]).distribute(planId)).to.be.revertedWith('CLIFF_NOT_REACHED()');

        await ethers.provider.send('evm_increaseTime', [vestingPeriodSeconds]);
        await ethers.provider.send('evm_mine', []);

        await expect(vesting.connect(accounts[1]).distribute(planId)).to.emit(vesting, 'DistributeAward')
            .withArgs(planId, accounts[0].address, mockToken.address, periodicGrant, periodicGrant, totalGrant - periodicGrant);

        expect(await mockToken.balanceOf(accounts[0].address)).to.equal(periodicGrant);

        await ethers.provider.send('evm_increaseTime', [Math.floor(vestingPeriodSeconds / 2)]);
        await ethers.provider.send('evm_mine', []);

        await expect(vesting.connect(accounts[1]).distribute(planId)).to.be.revertedWith('INCOMPLETE_PERIOD()');

        await ethers.provider.send('evm_increaseTime', [vestingPeriodSeconds * 3]);
        await ethers.provider.send('evm_mine', []);

        await expect(vesting.connect(accounts[1]).distribute(planId)).to.emit(vesting, 'DistributeAward')
            .withArgs(planId, accounts[0].address, mockToken.address, periodicGrant, periodicGrant * 3, totalGrant - periodicGrant * 4);

        expect(await mockToken.balanceOf(accounts[0].address)).to.equal(periodicGrant * 4);

        const details = await vesting.planDetails(planId);
        expect(details[0]['amount']).to.equal(periodicGrant);
    });

    it('Simple Termination Test', async () => {
        mockToken.connect(deployer).approve(vesting.address, '1000');

        const headLevel = await ethers.provider.getBlockNumber();
        const headBlock = await ethers.provider.getBlock(headLevel);

        const vestingPeriodSeconds = 60 * 60 * 1;
        const periodicGrant = 100;
        const periods = 10;
        const totalGrant = periodicGrant * periods;
        const cliffSeconds = headBlock.timestamp + vestingPeriodSeconds;

        const planId = getPlanId(accounts[1].address, deployer.address, mockToken.address, periodicGrant, cliffSeconds, vestingPeriodSeconds, periods);

        const initialSponsorBalance = await mockToken.balanceOf(deployer.address);

        await expect(vesting.connect(deployer).create(
            accounts[1].address,
            mockToken.address,
            periodicGrant,
            cliffSeconds,
            vestingPeriodSeconds,
            periods,
            'Simple Vest'
        )).to.emit(vesting, 'CreatePlan')
            .withArgs(accounts[1].address, deployer.address, mockToken.address, periodicGrant, cliffSeconds, vestingPeriodSeconds, periods, 'Simple Vest', planId);

        await ethers.provider.send('evm_increaseTime', [vestingPeriodSeconds * 6 + 10]);
        await ethers.provider.send('evm_mine', []);

        await expect(vesting.connect(deployer).terminate(planId)).to.emit(vesting, 'DistributeAward')
            .withArgs(planId, accounts[1].address, mockToken.address, periodicGrant, periodicGrant * 6, totalGrant - periodicGrant * 6);

        expect(await mockToken.balanceOf(accounts[1].address)).to.equal(periodicGrant * 6);

        const updatedSponsorBalance = await mockToken.balanceOf(deployer.address);
        expect(updatedSponsorBalance).to.eq(initialSponsorBalance - periodicGrant * 6);
    });

    it('Partial Claim Termination Test', async () => {
        mockToken.connect(deployer).approve(vesting.address, '1000');

        const headLevel = await ethers.provider.getBlockNumber();
        const headBlock = await ethers.provider.getBlock(headLevel);

        const vestingPeriodSeconds = 60 * 60 * 1;
        const periodicGrant = 100;
        const periods = 10;
        const totalGrant = periodicGrant * periods;
        const cliffSeconds = headBlock.timestamp + vestingPeriodSeconds;

        const planId = getPlanId(accounts[1].address, deployer.address, mockToken.address, periodicGrant, cliffSeconds, vestingPeriodSeconds, periods);

        const initialRecipientBalance = await mockToken.balanceOf(accounts[1].address);
        const initialSponsorBalance = await mockToken.balanceOf(deployer.address);

        await expect(vesting.connect(deployer).create(
            accounts[1].address,
            mockToken.address,
            periodicGrant,
            cliffSeconds,
            vestingPeriodSeconds,
            periods,
            'Simple Vest'
        )).to.emit(vesting, 'CreatePlan')
            .withArgs(accounts[1].address, deployer.address, mockToken.address, periodicGrant, cliffSeconds, vestingPeriodSeconds, periods, 'Simple Vest', planId);

        await ethers.provider.send('evm_increaseTime', [vestingPeriodSeconds + 10]);
        await ethers.provider.send('evm_mine', []);

        await expect(vesting.connect(accounts[1]).distribute(planId)).to.emit(vesting, 'DistributeAward')
            .withArgs(planId, accounts[1].address, mockToken.address, periodicGrant, periodicGrant, totalGrant - periodicGrant);

        await ethers.provider.send('evm_increaseTime', [vestingPeriodSeconds * 5 + 10]);
        await ethers.provider.send('evm_mine', []);

        await expect(vesting.connect(deployer).terminate(planId)).to.emit(vesting, 'DistributeAward')
            .withArgs(planId, accounts[1].address, mockToken.address, periodicGrant, periodicGrant * 5, totalGrant - periodicGrant * 6);

        expect(await mockToken.balanceOf(accounts[1].address)).to.equal(Number(initialRecipientBalance) + periodicGrant * 6);
        expect(await mockToken.balanceOf(deployer.address)).to.equal(Number(initialSponsorBalance) - periodicGrant * 6);
    });

    it('Misc Errors', async () => {
        await expect(vesting.unvestedBalance(1)).to.be.revertedWithCustomError(vesting, 'INVALID_PLAN');
        await expect(vesting.planDetails(1)).to.be.revertedWithCustomError(vesting, 'INVALID_PLAN');
        await expect(vesting.distribute(1)).to.be.revertedWithCustomError(vesting, 'INVALID_PLAN');
        await expect(vesting.terminate(1)).to.be.revertedWithCustomError(vesting, 'INVALID_PLAN');

    });
});

function getPlanId(recipient, sponsor, token, amount, cliff, periodDuration, periods) {
    const a = ethers.utils.solidityPack(
        ['address', 'address', 'address', 'uint256', 'uint256', 'uint256', 'uint256'],
        [recipient, sponsor, token, amount, cliff, periodDuration, periods]
    );
    const b = ethers.utils.keccak256(a);
    const c = ethers.BigNumber.from(b);

    return c.toString();
}
