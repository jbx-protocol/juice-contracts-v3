import { expect } from 'chai';
import { ethers } from 'hardhat';
import * as hre from 'hardhat';
import { BigNumber } from 'ethers';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import * as helpers from '@nomicfoundation/hardhat-network-helpers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { abiFromAddress, getPlatformConstant } from '../../../scripts/lib/lib';

const testNetwork = 'goerli';

async function deployContract(contractName: string, constructorArgs: any[], deployer: SignerWithAddress, libraries: { [key: string]: string } = {}): Promise<any> {
    const contractFactory = await hre.ethers.getContractFactory(contractName, { libraries, signer: deployer });
    const contractInstance = await contractFactory.connect(deployer).deploy(...constructorArgs);
    await contractInstance.deployed();
    return contractInstance;
}

/**
 * This test requires forked mainnet to run
 */
describe(`Deployer workflow tests (forked ${testNetwork})`, () => {
    const platformDeploymentLogPath = `./deployments/${testNetwork}/platform.json`;

    const JBCurrencies_ETH = getPlatformConstant('JBCurrencies_ETH', 1, platformDeploymentLogPath);
    const JBCurrencies_USD = getPlatformConstant('JBCurrencies_USD', 2, platformDeploymentLogPath);
    const ethToken = getPlatformConstant('ethToken', '0x000000000000000000000000000000000000EEEe', platformDeploymentLogPath);
    const usdToken = getPlatformConstant('usdToken', '0x6B175474E89094C44Da98b954EedeAC495271d0F', platformDeploymentLogPath);
    const chainlinkV2UsdEthPriceFeed = '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419' // getPlatformConstant('chainlinkV2UsdEthPriceFeed', '0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e', platformDeploymentLogPath);

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

    let projectId;

    before('Initialize accounts', async () => {
        const testAddresses = ['0xbeeF69b41A166A8696478F117cE92DbaC35250F4', '0xC38ace8d13c4EdBc0deD20803bcbA7B3497947BD', '0x715ec973818B1c262EF89A5957E3fE76c2f8C982'];

        const testBalance = ethers.utils.parseEther('10').toHexString();
        for await (const address of testAddresses) {
            await hre.network.provider.request({ method: 'hardhat_impersonateAccount', params: [address] });
            await hre.network.provider.send('hardhat_setBalance', [address, testBalance]);
            testAccounts.push(await ethers.getSigner(address));
            const balance = await ethers.provider.getBalance(address);
        }
    });

    before('Initialize defi hooks', async () => {
        let tx;

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
        expect(balance).to.be.greaterThan(ethers.utils.parseEther('1000'));
    });

    before('Deploy platform', async () => {
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
                daiToken.address,
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
    });

    before('Deploy platform project', async () => {
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

        const duration = 3600 * 24 * 30; // 30 days
        const weight = hre.ethers.BigNumber.from('1000000000000000000000000'); // 1M tokens/eth
        const discountRate = 0; // 0%
        const ballot = jb3DayReconfigurationBufferBallot.address;
        const fundingCycleData = [duration, weight, discountRate, ballot];

        const allowSetTerminals = false;
        const allowSetController = true;
        const pauseTransfer = true;
        const global = [allowSetTerminals, allowSetController, pauseTransfer];

        const reservedRate = 5000; // 50%
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
            distributionLimit: '70000000000000000000000', // 70_000
            distributionLimitCurrency: JBCurrencies_USD,
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
    });

    before('Deploy sample project', async () => {
        const deployer = testAccounts[0];

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
        let configuration, memo, owner;
        [configuration, projectId, memo, owner] = receipt.events.filter(e => e.event === 'LaunchProject')[0].args;

        tx = await jbTokenStore.connect(deployer).issueFor(projectId, 'Ah ah ah', 'AAA');
        receipt = await tx.wait();
    });

    it('Test setHedgeParameters()', async function () {
        const deployer = testAccounts[0];

        let tx = daiHedgeDelegate.connect(deployer).setHedgeParameters(
            projectId,
            true, // applyHedge
            6_000, // ethShare 60%
            500, // balanceThreshold 5%
            ethers.utils.parseEther('0.5'), // ethThreshold
            ethers.utils.parseEther('500'), // usdThreshold
            { liveQuote: true, defaultEthTerminal: true, defaultUsdTerminal: true });

        await expect(tx).not.to.be.reverted;

        tx = daiHedgeDelegate.connect(testAccounts[1]).setHedgeParameters(
            projectId,
            true, // applyHedge
            6_000, // ethShare 60%
            500, // balanceThreshold 5%
            ethers.utils.parseEther('0.5'), // ethThreshold
            ethers.utils.parseEther('500'), // usdThreshold
            { liveQuote: true, defaultEthTerminal: true, defaultUsdTerminal: true });

        await expect(tx).to.be.reverted;
    });

    it('Test smol eth contribution', async function () {
        const account = testAccounts[2];
        const amount = ethers.utils.parseEther('0.1');

        const tx = await jbETHPaymentTerminal.connect(account).pay(
            projectId,
            amount,
            ethToken, // token
            account.address, // beneficiary
            1, // minReturnedTokens
            false, // preferClaimedTokens
            '', // memo
            '0x00', // metadata
            { value: amount });
        const receipt = await tx.wait();
        const payEventArgs = receipt.events.filter(e => e.event === 'Pay')[0].args;
    });

    it('Test smol dai contribution', async function () {
        const account = testAccounts[1];
        const amount = ethers.utils.parseEther('100');

        let tx = await daiToken.connect(account)['approve(address,uint256)'](jbDAIPaymentTerminal.address, '0');
        await tx.wait();
        tx = await daiToken.connect(account)['approve(address,uint256)'](jbDAIPaymentTerminal.address, amount);
        await tx.wait();

        tx = await jbDAIPaymentTerminal.connect(account).pay(
            projectId,
            amount,
            daiToken.address, // token
            account.address, // beneficiary
            1, // minReturnedTokens
            false, // preferClaimedTokens
            '', // memo
            '0x00', // metadata
        );
        const receipt = await tx.wait();
        const payEventArgs = receipt.events.filter(e => e.event === 'Pay')[0].args;
    });

    it('Test large eth contribution', async function () {
        const account = testAccounts[2];
        const amount = ethers.utils.parseEther('0.5');

        const tx = await jbETHPaymentTerminal.connect(account).pay(
            projectId,
            amount,
            ethToken, // token
            account.address, // beneficiary
            1, // minReturnedTokens
            false, // preferClaimedTokens
            '', // memo
            '0x00', // metadata
            { value: amount });
        const receipt = await tx.wait();
        const payEventArgs = receipt.events.filter(e => e.event === 'Pay')[0].args;
    });

    it('Test large dai contribution', async function () {
        expect(false).to.equal(true);
    });

    it('Test eth redemption', async function () {
        expect(false).to.equal(true);
    });

    it('Test dai redemption', async function () {
        expect(false).to.equal(true);
    });

    it('Test eth distribution', async function () {
        expect(false).to.equal(true);
    });

    it('Test dai distribution', async function () {
        expect(false).to.equal(true);
    });
});
