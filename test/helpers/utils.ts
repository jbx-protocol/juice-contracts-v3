import { ethers, network } from 'hardhat';
import { BigNumber } from 'ethers';

/**
 * Grabs timestamp from Block or latest
 * @param {*} block
 * @returns
 */
export async function getTimestamp(block?) {
    return ethers.BigNumber.from((await ethers.provider.getBlock(block || 'latest')).timestamp);
}

/**
 * Fast Forwards EVM timestamp
 * @param {*} block
 * @param {number} seconds
 */
export async function fastForward(block, seconds) {
    const now = await getTimestamp();
    const timeSinceTimemark = now.sub(await getTimestamp(block));
    const fastforwardAmount = seconds.toNumber() - timeSinceTimemark.toNumber();
    await ethers.provider.send('evm_increaseTime', [fastforwardAmount]);
    await ethers.provider.send('evm_mine', []);
}

/**
 * Pack array of permission indexes into BigNumber
 * @param {number[]} permissionIndexes
 * @return {ethers.BigNumber}
 */
export function makePackedPermissions(permissionIndexes) {
    return permissionIndexes.reduce(
        (sum, i) => sum.add(ethers.BigNumber.from(2).pow(i)),
        ethers.BigNumber.from(0),
    );
}

/**
 * Create a test account
 * @param {string} address
 * @param {ethers.BigNumber} balance
 * @return {ethers.JsonRpcSigner}
 */
export async function impersonateAccount(
    address,
    balance = ethers.BigNumber.from('0x1000000000000000000000'),
) {
    await network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [address],
    });

    await network.provider.send('hardhat_setBalance', [address, balance.toHexString()]);

    return await ethers.getSigner(address);
}

/**
 * Set the ETH balance of a given address
 * 
 * @param {string} address
 * @param {number} balance
 */
export async function setBalance(
    address,
    balance?: number | BigNumber
) {
    const hexValue = balance ? ethers.BigNumber.from(balance).toHexString() : '0x1000000000000000000000';
    await network.provider.send('hardhat_setBalance', [address, hexValue]);
}

/**
 * Deploy a test JBToken contract
 * 
 * @param {string} name
 * @param {string} symbol
 * @param {number} projectId
 * @return {ethers.Contract}
 */
export async function deployJbToken(name, symbol, projectId) {
    const jbTokenFactory = await ethers.getContractFactory('JBToken');
    return await jbTokenFactory.deploy(name, symbol, projectId);
}

/**
 * Get a new date by adding days to now
 * @param {number} days
 * @return {date}
 */
export async function daysFromNow(days) {
    const date = await getTimestamp();
    return date.add(days * 24 * 60 * 60);
}

/**
 * Get a new date by adding days to the original date
 * @param {date} date
 * @param {number} days
 * @return {date}
 */
export function daysFromDate(date, days) {
    return date.add(days * 24 * 60 * 60);
}

/**
 * Get date in seconds
 * @param {date} date
 * @return {number}
 */
export function dateInSeconds(date) {
    return Math.floor(date.getTime() / 1000);
}

/**
 * Returns a mock FundingCyleMetadata packed into a BigNumber
 * @summary Should mirror the bit logic in JBFundingCycleMetadataResolver.sol.
 * @param {custom obj} e.g. packFundingCycleMetadata({ reservedRate: 3500, pausePay: 1 })
 * @return {ethers.BigNumber}
 * @note Passing in an empty obj will use default values below
 */
export function packFundingCycleMetadata({
    version = 1,
    global: {
        allowSetTerminals, // boolean
        allowSetController, // boolean
        pauseTransfer, // boolean
    } = {
        allowSetTerminals: false, // boolean
        allowSetController: false, // boolean
        pauseTransfer: false
    },
    reservedRate = 0, // percentage
    redemptionRate = 10000, // percentage
    ballotRedemptionRate = 10000, // percentage
    pausePay = false, // boolean
    pauseDistributions = false, // boolean
    pauseRedeem = false, // boolean
    pauseBurn = false, // boolean
    allowMinting = false, // boolean
    allowTerminalMigration = false, // boolean
    allowControllerMigration = false, // boolean
    holdFees = false, // boolean
    preferClaimedTokenOverride = false, // boolean
    useTotalOverflowForRedemptions = false, // boolean
    useDataSourceForPay = false, // boolean
    useDataSourceForRedeem = false, // boolean
    dataSource = `0x${'0'.repeat(40)}`, // address
    metadata = 0, // uint256
} = {}) {
    const one = ethers.BigNumber.from(1);

    let packed = ethers.BigNumber.from(version);
    if (allowSetTerminals) packed = packed.or(one.shl(8));
    if (allowSetController) packed = packed.or(one.shl(9));
    if (pauseTransfer) packed = packed.or(one.shl(10));
    packed = packed.or(ethers.BigNumber.from(reservedRate).shl(24));
    packed = packed.or(ethers.BigNumber.from(10000 - redemptionRate).shl(40));
    packed = packed.or(ethers.BigNumber.from(10000 - ballotRedemptionRate).shl(56));
    if (pausePay) packed = packed.or(one.shl(72));
    if (pauseDistributions) packed = packed.or(one.shl(73));
    if (pauseRedeem) packed = packed.or(one.shl(74));
    if (pauseBurn) packed = packed.or(one.shl(75));
    if (allowMinting) packed = packed.or(one.shl(76));
    if (allowTerminalMigration) packed = packed.or(one.shl(77));
    if (allowControllerMigration) packed = packed.or(one.shl(78));
    if (holdFees) packed = packed.or(one.shl(79));
    if (preferClaimedTokenOverride) packed = packed.or(one.shl(80));
    if (useTotalOverflowForRedemptions) packed = packed.or(one.shl(81));
    if (useDataSourceForPay) packed = packed.or(one.shl(82));
    if (useDataSourceForRedeem) packed = packed.or(one.shl(83));
    packed = packed.or(ethers.BigNumber.from(dataSource).shl(84));
    return packed.or(ethers.BigNumber.from(metadata).shl(244));
}

/**
 * Returns an array of JBSplits
 * @param {custom obj} count being the number of splits in the returned array, rest of the
 * object is a JBSplit
 * @return a JBSplit array of count objects
 */
export function makeSplits({
    count = 4,
    beneficiary = Array(count).fill(ethers.constants.AddressZero),
    preferClaimed = false,
    preferAddToBalance = false,
    percent = Math.floor(1000000000 / count),
    lockedUntil = 0,
    allocator = ethers.constants.AddressZero,
    projectId = 0,
} = {}) {
    let splits = [];
    for (let i = 0; i < count; i++) {
        splits.push({
            preferClaimed,
            preferAddToBalance,
            percent,
            projectId,
            beneficiary: beneficiary[i],
            lockedUntil,
            allocator,
        });
    }
    return splits;
}

/**
 * Returns a mock FundingCyleData struct
 * @summary Should create a struct based on the definition in structs/JBFundingCycleData.sol.
 * @param {custom obj} e.g. createFundingCycleData({ duration: 604800, weight: 1000000000000000000000000, discountRate: 0, ballot: constants.AddressZero })
 * @return {custom obj}
 * @note Passing in an empty obj will use default values below
 */
export function createFundingCycleData({
    duration = ethers.BigNumber.from(604800), // 1 week
    weight = ethers.BigNumber.from(10).pow(24), // 1 million with 18 decimals
    discountRate = ethers.BigNumber.from(0),
    ballot = ethers.constants.AddressZero,
} = {}) {
    return {
        duration,
        weight,
        discountRate,
        ballot,
    };
}