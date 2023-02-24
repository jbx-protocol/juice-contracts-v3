import * as fs from 'fs';
import * as hre from 'hardhat';
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from 'hardhat';

import { abiFromAddress } from '../lib/lib';
import { BigNumber } from 'ethers';

interface LogItem {
    address: string;
    contribution: BigNumber | number;
    contributionCurrency: number; // 0: eth, 1: dai
    contributionTokens: BigNumber | number;
    redeemedTokens: BigNumber | number;
    redemption: BigNumber | number;
    redemptionCurrency: number; // 0: eth, 1: dai
}

const JBCurrencies_ETH = 1;
const JBCurrencies_USD = 2;
const ethToken = '0x000000000000000000000000000000000000EEEe';
const usdToken = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const chainlinkV2UsdEthPriceFeed = '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419'; // mainnet

const wethAddress = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
const daiAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
const uniswapRouter3Address = '0xE592427A0AEce92De3Edee1F18E0157C05861564';

let testAccounts = [];

let jbTokenStore;
let jbController;
let jbSingleTokenPaymentTerminalStore;
let jbETHPaymentTerminal;
let jbDAIPaymentTerminal;
let jb3DayReconfigurationBufferBallot;
let daiHedgeDelegate;

let uniswapRouter3;
let daiToken;
let wethToken;

const platformDuration = 60 * 60 * 24 * 30; // seconds
const platformDiscountRate = 0; // 100% = 1_000_000_000
const platformReservedRate = 5000; // bps 50%
const platformRedemptionRate = 1_000; // bps 10%
const platformBallotRedemptionRate = 1_000; // bps 10%
const platformDistributionLimit = ethers.utils.parseUnits('100000', 18);
const platformDistributionLimitCurrency = JBCurrencies_USD;

let log: LogItem[] = [];

async function deployContract(contractName: string, constructorArgs: any[], deployer: SignerWithAddress, libraries: { [key: string]: string } = {}): Promise<any> {
    const contractFactory = await hre.ethers.getContractFactory(contractName, { libraries, signer: deployer });
    const contractInstance = await contractFactory.connect(deployer).deploy(...constructorArgs);
    await contractInstance.deployed();
    return contractInstance;
}

async function configureAccounts() {
    const testAddresses = ['0xbeeF69b41A166A8696478F117cE92DbaC35250F4', '0xC38ace8d13c4EdBc0deD20803bcbA7B3497947BD', '0x715ec973818B1c262EF89A5957E3fE76c2f8C982'];

    const testBalance = ethers.utils.parseEther('10').toHexString();
    for await (const address of testAddresses) {
        await hre.network.provider.request({ method: 'hardhat_impersonateAccount', params: [address] });
        await hre.network.provider.send('hardhat_setBalance', [address, testBalance]);
        testAccounts.push(await ethers.getSigner(address));
        const balance = await ethers.provider.getBalance(address);
        console.log(`assigned ${ethers.utils.formatEther(balance)} to ${address}`);
    }
}

async function configureDefi() {
    let tx, receipt;

    const wethAbi = await abiFromAddress(wethAddress, process.env.ETHERSCAN_KEY || '');
    wethToken = await ethers.getContractAt(wethAbi, wethAddress);

    const daiAbi = await abiFromAddress(daiAddress, process.env.ETHERSCAN_KEY || '');
    daiToken = await ethers.getContractAt(daiAbi, daiAddress);

    const uniswapRouter3Abi = await abiFromAddress(uniswapRouter3Address, process.env.ETHERSCAN_KEY || '');
    uniswapRouter3 = await ethers.getContractAt(uniswapRouter3Abi, uniswapRouter3Address);

    const oneEth = ethers.utils.parseEther('1');
    tx = await wethToken.connect(testAccounts[1]).deposit({ value: oneEth });
    await tx.wait();
    tx = await wethToken.connect(testAccounts[1]).approve(uniswapRouter3Address, oneEth);
    await tx.wait();

    const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;

    const uniswapParams = {
        tokenIn: wethAddress,
        tokenOut: daiAddress,
        fee: 3000,
        recipient: testAccounts[1].address,
        deadline: referenceTime + 60,
        amountIn: oneEth,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
    };

    tx = await uniswapRouter3.connect(testAccounts[1]).exactInputSingle(uniswapParams);
    await tx.wait();

    const balance = await daiToken.connect(testAccounts[1]).balanceOf(testAccounts[1].address);
    console.log(`${testAccounts[1].address} dai balance ${ethers.utils.formatUnits(balance.toString(), 18)}`);
}

async function deployPlatform() {
    const deployer = testAccounts[0];

    let jbETHERC20ProjectPayerDeployer = await deployContract('JBETHERC20ProjectPayerDeployer', [], deployer);
    let jbETHERC20SplitsPayerDeployer = await deployContract('JBETHERC20SplitsPayerDeployer', [], deployer);
    let jbOperatorStore = await deployContract('JBOperatorStore', [], deployer);
    let jbPrices = await deployContract('JBPrices', [deployer.address], deployer);
    let jbProjects = await deployContract('JBProjects', [jbOperatorStore.address], deployer);

    const transactionCount = await deployer.getTransactionCount();
    const expectedFundingCycleStoreAddress = hre.ethers.utils.getContractAddress({ from: deployer.address, nonce: transactionCount + 1 });
    let jbDirectory = await deployContract('JBDirectory', [jbOperatorStore.address, jbProjects.address, expectedFundingCycleStoreAddress, deployer.address], deployer);

    let jbFundingCycleStore = await deployContract('JBFundingCycleStore', [jbDirectory.address], deployer);
    jbTokenStore = await deployContract('JBTokenStore', [jbOperatorStore.address, jbProjects.address, jbDirectory.address, jbFundingCycleStore.address], deployer);
    let jbSplitsStore = await deployContract('JBSplitsStore', [jbOperatorStore.address, jbProjects.address, jbDirectory.address], deployer);
    jbController = await deployContract('JBController', [jbOperatorStore.address, jbProjects.address, jbDirectory.address, jbFundingCycleStore.address, jbTokenStore.address, jbSplitsStore.address], deployer);
    jbSingleTokenPaymentTerminalStore = await deployContract('JBSingleTokenPaymentTerminalStore', [jbDirectory.address, jbFundingCycleStore.address, jbPrices.address], deployer);
    let jbCurrencies = await deployContract('JBCurrencies', [], deployer);
    jbETHPaymentTerminal = await deployContract('JBETHPaymentTerminal', [JBCurrencies_ETH, jbOperatorStore.address, jbProjects.address, jbDirectory.address, jbSplitsStore.address, jbPrices.address, jbSingleTokenPaymentTerminalStore.address, deployer.address], deployer);

    jbDAIPaymentTerminal = await deployContract(
        'JBERC20PaymentTerminal',
        [
            usdToken,
            JBCurrencies_USD,
            JBCurrencies_ETH,
            2, // _payoutSplitsGroup, 2 = eth
            jbOperatorStore.address,
            jbProjects.address,
            jbDirectory.address,
            jbSplitsStore.address,
            jbPrices.address,
            jbSingleTokenPaymentTerminalStore.address,
            deployer.address],
        deployer
    );

    daiHedgeDelegate = await deployContract(
        'DaiHedgeDelegate', [jbOperatorStore.address, jbDirectory.address, jbProjects.address, jbETHPaymentTerminal.address, jbDAIPaymentTerminal.address, jbSingleTokenPaymentTerminalStore.address],
        deployer);

    const daySeconds = 60 * 60 * 24;
    let jb1DayReconfigurationBufferBallot = await deployContract('JBReconfigurationBufferBallot', [daySeconds], deployer);
    jb3DayReconfigurationBufferBallot = await deployContract('JBReconfigurationBufferBallot', [daySeconds * 3], deployer);
    let jb7DayReconfigurationBufferBallot = await deployContract('JBReconfigurationBufferBallot', [daySeconds * 7], deployer);

    let tx = await jbDirectory.connect(deployer)['setIsAllowedToSetFirstController(address,bool)'](jbController.address, true);
    await tx.wait();

    let jbChainlinkV3PriceFeed = await deployContract('JBChainlinkV3PriceFeed', [chainlinkV2UsdEthPriceFeed], deployer);
    tx = await jbPrices.connect(deployer)['addFeedFor(uint256,uint256,address)'](JBCurrencies_USD, JBCurrencies_ETH, jbChainlinkV3PriceFeed.address);
    await tx.wait();

    console.log('deployed platform contracts');
}

async function deployPlatformProject() {
    const deployer = testAccounts[0];

    let reserveTokenSplits = [];
    let payoutSplits = [];

    reserveTokenSplits.push({
        preferClaimed: false,
        preferAddToBalance: false,
        percent: '500000000',
        projectId: 0,
        beneficiary: deployer.address,
        lockedUntil: 0,
        allocator: hre.ethers.constants.AddressZero,
    });

    payoutSplits.push({
        preferClaimed: false,
        preferAddToBalance: false,
        percent: '500000000',
        projectId: 0,
        beneficiary: deployer.address,
        lockedUntil: 0,
        allocator: hre.ethers.constants.AddressZero,
    });

    const groupedSplits = [{ group: 1, splits: reserveTokenSplits }, { group: 2, splits: payoutSplits }];

    const domain = 0;
    const projectMetadataCID = '';
    const projectMetadata = [projectMetadataCID, domain];

    const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
    const protocolLaunchDate = referenceTime - 1000;

    const duration = platformDuration;
    const weight = hre.ethers.BigNumber.from('1000000000000000000000000'); // 1M tokens/eth
    const discountRate = platformDiscountRate;
    const ballot = jb3DayReconfigurationBufferBallot.address;
    const fundingCycleData = [duration, weight, discountRate, ballot];

    const allowSetTerminals = false;
    const allowSetController = true;
    const pauseTransfer = true;
    const global = [allowSetTerminals, allowSetController, pauseTransfer];

    const reservedRate = platformReservedRate;
    const redemptionRate = platformRedemptionRate;
    const ballotRedemptionRate = platformBallotRedemptionRate;
    const pausePay = false;
    const pauseDistributions = false;
    const pauseRedeem = false;
    const pauseBurn = false;
    const allowMinting = false;
    const allowTerminalMigration = false;
    const allowControllerMigration = false;
    const holdFees = false;
    const preferClaimedTokenOverride = false;
    const useTotalOverflowForRedemptions = false;
    const useDataSourceForPay = false;
    const useDataSourceForRedeem = false;
    const dataSource = hre.ethers.constants.AddressZero;
    const metadata = 0;
    const fundingCycleMetadata = [
        global,
        reservedRate,
        redemptionRate,
        ballotRedemptionRate,
        pausePay,
        pauseDistributions,
        pauseRedeem,
        pauseBurn,
        allowMinting,
        allowTerminalMigration,
        allowControllerMigration,
        holdFees,
        preferClaimedTokenOverride,
        useTotalOverflowForRedemptions,
        useDataSourceForPay,
        useDataSourceForRedeem,
        dataSource,
        metadata
    ];

    const fundAccessConstraints = [{
        terminal: jbETHPaymentTerminal.address,
        token: ethToken,
        distributionLimit: platformDistributionLimit,
        distributionLimitCurrency: platformDistributionLimitCurrency,
        overflowAllowance: 0,
        overflowAllowanceCurrency: JBCurrencies_ETH
    }];

    const tx = await jbController.connect(deployer)['launchProjectFor(address,(string,uint256),(uint256,uint256,uint256,address),((bool,bool,bool),uint256,uint256,uint256,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,address,uint256),uint256,(uint256,(bool,bool,uint256,uint256,address,uint256,address)[])[],(address,address,uint256,uint256,uint256,uint256)[],address[],string)'](
        deployer.address,
        projectMetadata,
        fundingCycleData,
        fundingCycleMetadata,
        protocolLaunchDate,
        groupedSplits,
        fundAccessConstraints,
        [jbETHPaymentTerminal.address],
        ''
    );
    await tx.wait();

    console.log('deployed root project');
}

async function deploySampleProject() {
    const [deployer]: SignerWithAddress[] = await hre.ethers.getSigners();

    let reserveTokenSplits = [];
    let payoutSplits = [];

    const primaryBeneficiary = deployer.address;

    payoutSplits.push({
        preferClaimed: false,
        preferAddToBalance: false,
        percent: 1_000_000_000, // 100%
        projectId: 0,
        beneficiary: primaryBeneficiary,
        lockedUntil: 0,
        allocator: hre.ethers.constants.AddressZero,
    });

    const groupedSplits = [{ group: 1, splits: reserveTokenSplits }, { group: 2, splits: payoutSplits }];

    const domain = 0;
    const projectMetadataCID = '';
    const projectMetadata = [projectMetadataCID, domain];

    const referenceTime = (await ethers.provider.getBlock('latest')).timestamp;
    const protocolLaunchDate = referenceTime - 100;

    const duration = 0;// 10 * 60; // 10 min
    const weight = hre.ethers.BigNumber.from('1000000000000000000000000'); // 1M tokens/eth
    const discountRate = 0; // 0%
    const ballot = hre.ethers.constants.AddressZero;
    const fundingCycleData = [duration, weight, discountRate, ballot];

    const allowSetTerminals = true;
    const allowSetController = true;
    const pauseTransfer = true;
    const global = [allowSetTerminals, allowSetController, pauseTransfer];

    const reservedRate = 0;
    const redemptionRate = 10_000; // 100%
    const ballotRedemptionRate = 10_000;
    const pausePay = false;
    const pauseDistributions = false;
    const pauseRedeem = false;
    const pauseBurn = false;
    const allowMinting = false;
    const allowTerminalMigration = false;
    const allowControllerMigration = false;
    const holdFees = false;
    const preferClaimedTokenOverride = false;
    const useTotalOverflowForRedemptions = true;
    const useDataSourceForPay = true;
    const useDataSourceForRedeem = false; // NOTE: right now, DaiHedgeDelegate does not on redeem anyway
    const dataSource = daiHedgeDelegate.address;
    const metadata = 0;
    const fundingCycleMetadata = [
        global,
        reservedRate,
        redemptionRate,
        ballotRedemptionRate,
        pausePay,
        pauseDistributions,
        pauseRedeem,
        pauseBurn,
        allowMinting,
        allowTerminalMigration,
        allowControllerMigration,
        holdFees,
        preferClaimedTokenOverride,
        useTotalOverflowForRedemptions,
        useDataSourceForPay,
        useDataSourceForRedeem,
        dataSource,
        metadata
    ];

    const fundAccessConstraints = [{
        terminal: jbETHPaymentTerminal.address,
        token: ethToken,
        distributionLimit: ethers.utils.parseEther('0.01'),
        distributionLimitCurrency: JBCurrencies_ETH,
        overflowAllowance: ethers.utils.parseEther('0.01'),
        overflowAllowanceCurrency: JBCurrencies_ETH
    }, {
        terminal: jbDAIPaymentTerminal.address,
        token: usdToken,
        distributionLimit: '0',
        distributionLimitCurrency: JBCurrencies_USD,
        overflowAllowance: 0,
        overflowAllowanceCurrency: JBCurrencies_USD
    }];

    const terminals = [jbETHPaymentTerminal.address, jbDAIPaymentTerminal.address];

    let tx, receipt;

    tx = await jbController.connect(deployer)['launchProjectFor(address,(string,uint256),(uint256,uint256,uint256,address),((bool,bool,bool),uint256,uint256,uint256,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,address,uint256),uint256,(uint256,(bool,bool,uint256,uint256,address,uint256,address)[])[],(address,address,uint256,uint256,uint256,uint256)[],address[],string)'](
        deployer.address,
        projectMetadata,
        fundingCycleData,
        fundingCycleMetadata,
        protocolLaunchDate,
        groupedSplits,
        fundAccessConstraints,
        terminals,
        ''
    );
    receipt = await tx.wait();

    const [configuration, projectId, memo, owner] = receipt.events.filter(e => e.event === 'LaunchProject')[0].args;

    tx = await jbTokenStore.connect(deployer).issueFor(projectId, 'Ah ah ah', 'AAA');
    receipt = await tx.wait();

    const issueEventArgs = receipt.events.filter(e => e.event === 'Issue')[0].args;

    console.log(`deployed sample project: ${projectId}`);

    return projectId;
}

async function configureSampleProject(projectId: number) {
    const [deployer]: SignerWithAddress[] = await hre.ethers.getSigners();

    const tx = await daiHedgeDelegate.connect(deployer).setHedgeParameters(
        projectId,
        true, // applyHedge
        6_000, // ethShare 60%
        500, // balanceThreshold 5%
        ethers.utils.parseEther('0.5'), // ethThreshold
        ethers.utils.parseEther('500'), // usdThreshold
        { liveQuote: true, defaultEthTerminal: true, defaultUsdTerminal: true });
    await tx.wait();
}

async function contribute(projectId, account, currency, amount): Promise<BigNumber> {
    let tx, receipt;

    if (currency == JBCurrencies_ETH) {
        tx = await jbETHPaymentTerminal.connect(account).pay(
            projectId,
            amount,
            ethToken, // token
            account.address, // beneficiary
            1, // minReturnedTokens
            false, // preferClaimedTokens
            '', // memo
            '0x00', // metadata
            { value: amount });
        receipt = await tx.wait();
    } else if (currency == JBCurrencies_USD) {
        tx = await daiToken.connect(account)['approve(address,uint256)'](jbDAIPaymentTerminal.address, '0');
        await tx.wait();
        tx = await daiToken.connect(account)['approve(address,uint256)'](jbDAIPaymentTerminal.address, amount);
        await tx.wait();

        tx = await jbDAIPaymentTerminal.connect(account).pay(
            projectId,
            amount,
            daiAddress, // token
            account.address, // beneficiary
            1, // minReturnedTokens
            false, // preferClaimedTokens
            '', // memo
            '0x00', // metadata
        );
        receipt = await tx.wait();
    }

    const payEventArgs = receipt.events.filter(e => e.event === 'Pay')[0].args;

    return BigNumber.from(payEventArgs['beneficiaryTokenCount']);
}

async function redeemTokens(projectId, account, currency, amount): Promise<BigNumber> {
    let tx, receipt;

    if (currency === 1) {
        tx = await jbETHPaymentTerminal.connect(account).redeemTokensOf(
            account.address, // holder
            projectId,
            amount, // tokenCount (to redeem)
            ethToken, // token (address to receive)
            1, // _minReturnedTokens (to receive)
            account.address, // beneficiary
            '', // memo
            '0x00' // metadata
        );
        receipt = await tx.wait();
    } else if (currency === 2) {
        tx = await jbDAIPaymentTerminal.connect(account).redeemTokensOf(
            account.address, // holder
            projectId,
            amount, // tokenCount (to redeem)
            usdToken, // token (address to receive)
            1, // _minReturnedTokens (to receive)
            account.address, // beneficiary
            '', // memo
            '0x00' // metadata
        );
        receipt = await tx.wait();
    }

    const redeemTokensEventArgs = receipt.events.filter(e => e.event === 'RedeemTokens')[0].args;

    return BigNumber.from(redeemTokensEventArgs['reclaimedAmount']);
}

async function applyContributions() {
    const contributionContent = fs.readFileSync('scripts/workflow/contributions.csv').toString().split('\n');
    const columnNames = contributionContent[0].split(',');
    const contributionList = contributionContent.slice(1);
    const blockLevelIndex = columnNames.indexOf('blockNumber');
    const timestampIndex = columnNames.indexOf('timestamp');
    const senderIndex = columnNames.indexOf('sender');
    const valueIndex = columnNames.indexOf('value');
    const symbolIndex = columnNames.indexOf('symbol');

    const ethContributions = contributionList.map(r => r.split(','));

    let testBalance = ethers.utils.parseEther('100000').toHexString();
    if (testBalance.startsWith('0x0')) {
        testBalance = '0x' + testBalance.slice(3); // NOTE: cannot have a leading 0
    }

    let contributionLog = '';
    for await (const r of ethContributions) {
        let address = r[senderIndex];
        let account;

        try {
            await hre.network.provider.request({ method: 'hardhat_impersonateAccount', params: [address] });
            await hre.network.provider.send('hardhat_setBalance', [address, testBalance]);
            account = await ethers.getSigner(address);
        } catch {
            console.log(`failed to impersonate "${address}"`);
            continue;
        }

        let value = BigNumber.from(0);
        if (r[symbolIndex] === 'eth') {
            value = BigNumber.from(r[valueIndex].replace(/"/g, ''));
        } else {
            value = BigNumber.from(r[valueIndex].replace(/"/g, ''))
                .div(getPrice(new Date(Number(r[timestampIndex]))) * 100)
                .mul(100);
            console.log(`converted ${ethers.utils.formatUnits(r[valueIndex].replace(/"/g, ''), 18)} to ${ethers.utils.formatUnits(value, 18)} at ${getPrice(new Date(Number(r[timestampIndex])))}`)
        }

        // let value = ethers.utils.parseEther('1');

        if (value.eq(0)) { continue; }

        // advance to block if using funding cycles

        const tokenAmount = await contribute(1, account, JBCurrencies_ETH, value);
        contributionLog += `${address},${value},${tokenAmount}\n`;

        console.log(`contributed ${ethers.utils.formatUnits(value, 18)} eth for ${ethers.utils.formatUnits(tokenAmount, 18)} by ${truncateAddress(account.address)}`);

        log.push({
            address: account.address,
            contribution: value,
            contributionCurrency: 0,
            contributionTokens: tokenAmount,
            redeemedTokens: 0,
            redemption: 0,
            redemptionCurrency: 0
        });
    }

    contributionLog = 'account,contribution,tokens\n' + contributionLog;
    fs.writeFileSync('scripts/workflow/token.csv', contributionLog);
}

async function applyRedemptions() {
    const tokenContent = fs.readFileSync('scripts/workflow/token.csv').toString().split('\n');
    const columnNames = tokenContent[0].split(',');
    const tokenList = tokenContent.slice(1).filter(r => r.length > 0).map(r => r.split(','));
    const accountIndex = columnNames.indexOf('account');
    const contributionIndex = columnNames.indexOf('contribution');
    const tokensIndex = columnNames.indexOf('tokens');

    let redemptionLog = '';
    let logIndex = 0;
    for await (const r of tokenList) {
        let address = r[accountIndex];
        let account;

        try {
            account = await ethers.getSigner(address);
        } catch {
            console.log(`failed to impersonate "${address}"`);
            continue;
        }

        const halfTokens = BigNumber.from(r[tokensIndex].replace(/"/g, '')).div(2);
        if (halfTokens.eq(0)) { logIndex++; continue; }

        try {
            const redeemedAmount = await redeemTokens(1, account, JBCurrencies_ETH, halfTokens);
            redemptionLog += `${address},${halfTokens},${redeemedAmount}\n`;

            console.log(`redeemed ${ethers.utils.formatUnits(halfTokens, 18)} for ${ethers.utils.formatUnits(redeemedAmount, 18)} by ${truncateAddress(account.address)}`);

            const logItem = log[logIndex];
            if (logItem.address === account.address) {
                log[logIndex].redeemedTokens = halfTokens;
                log[logIndex].redemption = redeemedAmount;
            } else {
                console.error('Log item mismatch')
            }
        } catch {
            console.error(`failed to redeem for ${account.address} at ${logIndex}`);
        }
        logIndex++;
    }

    redemptionLog = 'account,tokens,redemption\n' + redemptionLog;
    fs.writeFileSync('scripts/workflow/redemption.csv', redemptionLog);
}

async function addProjectBalance(projectId, account, currency, amount) {
    let hexAmount = amount.add(ethers.utils.parseEther('1')).toHexString();
    if (hexAmount.startsWith('0x0')) {
        hexAmount = '0x' + hexAmount.slice(3); // NOTE: cannot have a leading 0
    }

    await hre.network.provider.send('hardhat_setBalance', [account.address, hexAmount]);

    const tx = await jbETHPaymentTerminal.connect(account).addToBalanceOf(
        projectId,
        amount,
        ethToken, // token
        '', // memo
        '0x00', // metadata
        { value: amount });
    const receipt = await tx.wait();
}

async function projectBalance(terminal = jbETHPaymentTerminal.address, projectId = 1): Promise<BigNumber> {
    const projectBalance = await jbSingleTokenPaymentTerminalStore.balanceOf(terminal, projectId);
    console.log('project balance', ethers.utils.formatUnits(projectBalance, 18), 'eth');

    return projectBalance;
}

function getPrice(timestamp: Date): number {
    const static2022Prices = [
        [
            3763.03, 3831.29, 3761.33, 3788.88, 3533.49, 3411.56, 3197.71, 3079.15, 3151.95, 3086.63, 3236.53, 3373.7,
            3239.95, 3307.95, 3326.69, 3351.67, 3209.57, 3160.99, 3085.52, 3004.89, 2561.3, 2413.62, 2542.15, 2440.8, 2459.25,
            2463.58, 2424.65, 2546.87, 2599.98, 2603.13, 2688.89,
        ], // jan
        [
            2792.03, 2679.12, 2693.68, 2985.95, 3014.92, 3061.91, 3142.03, 3114.8, 3245.54, 3063.41, 2929.14, 2919.14,
            2870.08, 2930.46, 3185.97, 3122.95, 2879.78, 2780.48, 2764.2, 2621.33, 2567.71, 2635.24, 2579.16, 2596.44, 2775.1,
            2777.46, 2622.05, 2924.63,
        ], // feb
        [
            2977.18, 2951.27, 2835.84, 2624.28, 2665.22, 2552.77, 2495.48, 2575.2, 2727.73, 2606.66, 2555.71, 2566.67, 2516.6,
            2588.36, 2618.54, 2774.69, 2813.21, 2941.02, 2952.05, 2860.76, 2894.73, 2970.25, 3039.81, 3113.14, 3103.85,
            3149.89, 3297.72, 3330.34, 3404.5, 3384.35, 3281.42,
        ], // mar
        [
            3457.85, 3444.48, 3521.34, 3521.2, 3408.92, 3172.09, 3229.84, 3194.61, 3261.36, 3201.7, 2978.17, 3029.57, 3119.0,
            3022.37, 3042.56, 3061.08, 2990.83, 3054.3, 3101.86, 3078.12, 2984.44, 2964.01, 2936.97, 2923.52, 3004.42,
            2809.92, 2888.65, 2938.87, 2817.69, 2735.6,
        ], // apr
        [
            2825.68, 2858.59, 2779.91, 2941.11, 2745.93, 2693.1, 2634.8, 2520.46, 2229.42, 2341.97, 2074.41, 1953.25, 2007.03,
            2054.0, 2143.66, 2018.8, 2089.32, 1911.14, 2015.27, 1958.33, 1973.5, 2040.67, 1971.22, 1976.92, 1940.57, 1791.78,
            1723.98, 1791.05, 1811.36, 1997.17, 1940.17,
        ], // may
        [
            1816.06, 1833.49, 1774.72, 1804.31, 1805.61, 1858.82, 1811.69, 1791.56, 1786.14, 1660.91, 1527.45, 1435.81,
            1203.37, 1210.21, 1237.16, 1067.43, 1084.9, 994.02, 1127.19, 1128.07, 1125.44, 1048.43, 1142.48, 1223.71, 1241.44,
            1197.2, 1190.18, 1142.53, 1099.09, 1073.28,
        ], // jun
        [1058.86, 1065.07, 1073.43, 1150.12, 1133.96, 1185.53, 1237.6, 1215.42, 1216.21, 1167.62, 1140.18], // jul til 11
    ];

    try {
        return static2022Prices[timestamp.getUTCMonth()][timestamp.getUTCDate() - 1] || -1;
    } catch {
        return -1;
    }
}

function truncateAddress(address: string) {
    return address.slice(0, 6) + '...' + address.slice(-4);
}

function printLog() {
    console.log('address,contribution,contributionCurrency,contributionTokens,redeemedTokens,redemption,redemptionCurrency');

    for (const logItem of log) {
        let item = '';

        item += `${logItem.address},`;
        item += `${ethers.utils.formatUnits(logItem.contribution)},`;
        item += `${logItem.contributionCurrency},`;
        item += `${ethers.utils.formatUnits(logItem.contributionTokens)},`;
        item += `${ethers.utils.formatUnits(logItem.redeemedTokens)},`;
        item += `${ethers.utils.formatUnits(logItem.redemption)},`;
        item += `${logItem.redemptionCurrency}`;

        console.log(item);
    }
}

async function main() {
    let projectId = 0;

    console.log('running contribution simulation');
    console.log(`cycle duration: ${platformDuration / 60} minutes`);
    console.log(`cycle discount rate: ${platformDiscountRate} bps`);
    console.log(`reserved rate: ${platformReservedRate} bps`);
    console.log(`redemption rate: ${platformRedemptionRate} bps`);
    console.log(`ballot redemption rate: ${platformBallotRedemptionRate} bps`);
    console.log(`distribution limit: ${BigNumber.from(platformDistributionLimit).div(BigNumber.from('1000000000000000000')).toString()} ${platformDistributionLimitCurrency === JBCurrencies_USD ? 'usd' : 'eth'}`);

    await configureAccounts();
    await configureDefi();
    await deployPlatform();
    await deployPlatformProject();
    // projectId = await deploySampleProject();
    // await configureSampleProject(projectId);

    await projectBalance();
    await applyContributions();
    // let balance = await projectBalance();
    // await addProjectBalance(1, testAccounts[2], 0, balance);
    await projectBalance();
    await applyRedemptions();
    await projectBalance();

    printLog();
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/workflow/contributions.ts
