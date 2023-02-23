import * as hre from 'hardhat';
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from 'hardhat';

import { getContractRecord, getPlatformConstant } from '../lib/lib';
import { BigNumber } from 'ethers';

async function deploySampleProject() {
    const [deployer]: SignerWithAddress[] = await hre.ethers.getSigners();

    const jbETHPaymentTerminalRecord = getContractRecord('JBETHPaymentTerminal');
    const jbDAIPaymentTerminalRecord = getContractRecord('JBDAIPaymentTerminal');
    const daiHedgeDelegateRecord = getContractRecord('DaiHedgeDelegate');

    const jbControllerRecord = getContractRecord('JBController');
    const jbControllerContract = await hre.ethers.getContractAt(jbControllerRecord['abi'], jbControllerRecord['address'], deployer);

    const jbTokenStoreRecord = getContractRecord('JBTokenStore');
    const jbTokenStoreContract = await hre.ethers.getContractAt(jbTokenStoreRecord['abi'], jbTokenStoreRecord['address'], deployer);

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

    const duration = 0; // seconds
    const weight = hre.ethers.utils.parseUnits('1000000', 18); // 1M tokens/eth
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
    const dataSource = daiHedgeDelegateRecord['address'];
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
        terminal: jbETHPaymentTerminalRecord['address'],
        token: getPlatformConstant('ethToken'),
        distributionLimit: ethers.utils.parseEther('0.1'),
        distributionLimitCurrency: getPlatformConstant('JBCurrencies_ETH'),
        overflowAllowance: ethers.utils.parseEther('0.1'),
        overflowAllowanceCurrency: getPlatformConstant('JBCurrencies_ETH')
    }, {
        terminal: jbDAIPaymentTerminalRecord['address'],
        token: getPlatformConstant('usdToken'),
        distributionLimit: ethers.utils.parseUnits('100', 18),
        distributionLimitCurrency: getPlatformConstant('JBCurrencies_USD'),
        overflowAllowance: 0,
        overflowAllowanceCurrency: getPlatformConstant('JBCurrencies_USD')
    }];

    const terminals = [jbETHPaymentTerminalRecord['address'], jbDAIPaymentTerminalRecord['address']];

    let tx, receipt;

    tx = await jbControllerContract.connect(deployer)['launchProjectFor(address,(string,uint256),(uint256,uint256,uint256,address),((bool,bool,bool),uint256,uint256,uint256,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,address,uint256),uint256,(uint256,(bool,bool,uint256,uint256,address,uint256,address)[])[],(address,address,uint256,uint256,uint256,uint256)[],address[],string)'](
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

    tx = await jbTokenStoreContract.connect(deployer).issueFor(projectId, 'Sample User Project', 'SUP');
    receipt = await tx.wait();

    const issueEventArgs = receipt.events.filter(e => e.event === 'Issue')[0].args;

    console.log(`deployed sample project: ${projectId} as ${deployer.address}`);

    return projectId;
}

async function configureSampleProject(projectId: number) {
    const [deployer]: SignerWithAddress[] = await hre.ethers.getSigners();

    const daiHedgeDelegateRecord = getContractRecord('DaiHedgeDelegate');
    const daiHedgeDelegateContract = await hre.ethers.getContractAt(daiHedgeDelegateRecord['abi'], daiHedgeDelegateRecord['address'], deployer);

    const tx = await daiHedgeDelegateContract.connect(deployer).setHedgeParameters(
        projectId,
        true, // applyHedge
        6_000, // ethShare 60%
        500, // balanceThreshold 5%
        ethers.utils.parseEther('0.5'), // ethThreshold
        ethers.utils.parseEther('500'), // usdThreshold
        { liveQuote: true, defaultEthTerminal: true, defaultUsdTerminal: true });
    await tx.wait();
}

async function main() {
    const projectId = await deploySampleProject();
    await configureSampleProject(projectId);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/platform/samples.ts --network goerli
