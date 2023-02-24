import * as hre from 'hardhat';
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from 'hardhat';

import { getContractRecord, getPlatformConstant } from '../lib/lib';
import { type FundingCycleInfo } from '../lib/extra';
import { BigNumber } from 'ethers';

async function deploySampleProject(fundingCycleInfo: FundingCycleInfo) {
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

    const duration = fundingCycleInfo.Duration;
    const weight = fundingCycleInfo.TokenMintRate;
    const discountRate = fundingCycleInfo.DiscountRate;
    const ballot = hre.ethers.constants.AddressZero;
    const fundingCycleData = [duration, weight, discountRate, ballot];

    const allowSetTerminals = fundingCycleInfo.TerminalConfiguration;
    const allowSetController = fundingCycleInfo.ControllerConfiguration;
    const pauseTransfer = false;
    const global = [allowSetTerminals, allowSetController, pauseTransfer];

    const reservedRate = fundingCycleInfo.ReserveRate;
    const redemptionRate = fundingCycleInfo.RedemptionRate;
    const ballotRedemptionRate = 10_000;
    const pausePay = !fundingCycleInfo.Payments;
    const pauseDistributions = !fundingCycleInfo.Distribution;
    const pauseRedeem = !fundingCycleInfo.Redemptions;
    const pauseBurn = false;
    const allowMinting = !fundingCycleInfo.TokenMinting;
    const allowTerminalMigration = !fundingCycleInfo.TerminalMigration;
    const allowControllerMigration = !fundingCycleInfo.ControllerMigration;
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
    console.log(`deployed sample project: ${projectId} as ${deployer.address} in ${receipt['transactionHash']} for ${receipt['gasUsed']} gas`);

    tx = await jbTokenStoreContract.connect(deployer).issueFor(projectId, 'Sample User Project', 'SUP');
    receipt = await tx.wait();

    const issueEventArgs = receipt.events.filter(e => e.event === 'Issue')[0].args;
    console.log(`deployed project token at ${issueEventArgs['token']} in ${receipt['transactionHash']} for ${receipt['gasUsed']} gas`)

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

async function deployPayers(projectId: number) {
    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;
    const [deployer]: SignerWithAddress[] = await hre.ethers.getSigners();
    const defaultPlatformFee = ethers.utils.parseEther('0.001');

    const jbDirectoryRecord = getContractRecord('JBDirectory');
    const jbOperatorStoreRecord = getContractRecord('JBOperatorStore');
    const jbProjectsRecord = getContractRecord('JBProjects');

    const deployerProxyRecord = getContractRecord('DeployerProxy', deploymentLogPath);
    const deployerProxyContract = await hre.ethers.getContractAt(deployerProxyRecord['abi'], deployerProxyRecord['address'], deployer);
    let tx = await deployerProxyContract.connect(deployer).deployProjectPayer(
        jbDirectoryRecord['address'],
        jbOperatorStoreRecord['address'],
        jbProjectsRecord['address'],
        projectId,
        deployer.address, // defaultBeneficiary
        true, // defaultPreferClaimedTokens
        false, // defaultPreferAddToBalance
        '', // defaultMemo
        '0x00', // defaultMetadata
        { value: defaultPlatformFee }
    );
    let receipt = await tx.wait();
    console.log(`deployed sample ThinProjectPayer in ${receipt['transactionHash']} for ${receipt['gasUsed']} gas`);

    const jbProjectPayerDeployerRecord = getContractRecord('JBETHERC20ProjectPayerDeployer');
    const jbProjectPayerDeployerContract = await hre.ethers.getContractAt(jbProjectPayerDeployerRecord['abi'], jbProjectPayerDeployerRecord['address'], deployer);

    tx = await jbProjectPayerDeployerContract.connect(deployer).deployProjectPayer(
        projectId,
        deployer.address,
        false, // defaultPreferClaimedTokens
        '', // defaultMemo
        '0x00', // defaultMetadata
        false, // defaultPreferAddToBalance
        jbDirectoryRecord['address'],
        deployer.address);
    receipt = await tx.wait();
    console.log(`deployed sample JBETHERC20ProjectPayer in ${receipt['transactionHash']} for ${receipt['gasUsed']} gas`);
}

async function deployNFTs() {
    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;
    const platformLogPath = `./deployments/${hre.network.name}/platform.json`;
    const [deployer]: SignerWithAddress[] = await hre.ethers.getSigners();
    const defaultPlatformFee = ethers.utils.parseEther('0.001');

    const deployerProxyRecord = getContractRecord('DeployerProxy', deploymentLogPath);
    const deployerProxyContract = await hre.ethers.getContractAt(deployerProxyRecord['abi'], deployerProxyRecord['address'], deployer);

    let tx = await deployerProxyContract.connect(deployer).deployNFToken(
        deployer.address, // owner,
        'NFT', // name,
        'NFT', // symbol
        'ipfs://token-metadata', // baseUri
        'ipfs://contract-metadata', // contractUri
        10000, // maxSupply
        ethers.utils.parseEther('0.001'), // unitPrice
        10, // mintAllowance
        false, // reveal
        { value: defaultPlatformFee }
    );
    let receipt = await tx.wait();

    const [contractType, tokenAddress] = receipt.events.filter(e => e.event === 'Deployment')[0].args;
    console.log(`deployed token clone at ${tokenAddress}`);

    console.log(`deployed sample NFToken in ${receipt['transactionHash']} for ${receipt['gasUsed']} gas`);

    const nfTokenRecord = getContractRecord('NFToken', platformLogPath);
    const nfTokenContract = await hre.ethers.getContractAt(nfTokenRecord['abi'], '0xbDD5ecF1b33f52231dB2ADa3eBed0F4b49b16Db1', deployer);

    tx = await nfTokenContract.connect(deployer).setRoyalties(deployer.address, 500);
    receipt = await tx.wait();
    console.log(`setRoyalties on NFToken in ${receipt['transactionHash']} for ${receipt['gasUsed']} gas`);

    tx = await nfTokenContract.connect(deployer).setPayoutReceiver(deployer.address);
    receipt = await tx.wait();
    console.log(`setPayoutReceiver on NFToken in ${receipt['transactionHash']} for ${receipt['gasUsed']} gas`);

    tx = await deployerProxyContract.connect(deployer).deployNFUToken(
        deployer.address, // owner,
        'NFT', // name,
        'NFT', // symbol
        'ipfs://token-metadata', // baseUri
        'ipfs://contract-metadata', // contractUri
        10000, // maxSupply
        ethers.utils.parseEther('0.001'), // unitPrice
        10, // mintAllowance
        { value: defaultPlatformFee }
    );
    receipt = await tx.wait();

    console.log(`deployed sample NFUToken in ${receipt['transactionHash']} for ${receipt['gasUsed']} gas`);
}

async function deployMixedPaymentSplitter(projectId) {
    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;
    const [deployer]: SignerWithAddress[] = await hre.ethers.getSigners();
    const defaultPlatformFee = ethers.utils.parseEther('0.001');

    const jbDirectoryRecord = getContractRecord('JBDirectory');

    const deployerProxyRecord = getContractRecord('DeployerProxy', deploymentLogPath);
    const deployerProxyContract = await hre.ethers.getContractAt(deployerProxyRecord['abi'], deployerProxyRecord['address'], deployer);

    let tx = await deployerProxyContract.connect(deployer).deployMixedPaymentSplitter(
        'Sample payer',
        [deployer.address], // payees,
        [projectId], // projects,
        [500_000, 500_000], // shares,
        jbDirectoryRecord['address'],
        deployer.address, // owner
        { value: defaultPlatformFee }
    );
    let receipt = await tx.wait();

    console.log(`deployed sample MixedPaymentSplitter in ${receipt['transactionHash']} for ${receipt['gasUsed']} gas`);
}

async function main() {
    const dualFundingCycleInfo: FundingCycleInfo = {
        Duration: 0, // seconds
        DistributionLimit: ethers.utils.parseEther('0.1'),
        DistributionCurrency: getPlatformConstant('JBCurrencies_ETH'),
        TokenMintRate: hre.ethers.utils.parseUnits('1000000', 18), // 1M tokens/eth
        ReserveRate: 5000, // bps
        RedemptionRate: 10_000, // bps
        DiscountRate: 0, // 100% = 1_000_000_000
        ReconfigurationStrategy: ethers.constants.AddressZero,
        Ballot: ethers.constants.AddressZero,
        Payments: true, // inverse of pausePay
        Redemptions: true,
        Distribution: true,
        TokenMinting: false,
        TerminalConfiguration: true,
        ControllerConfiguration: true,
        TerminalMigration: true,
        ControllerMigration: true,
        FundingAccessConstraints: [
            {
                Terminal: getContractRecord('JBETHPaymentTerminal')['address'],
                Token: getPlatformConstant('ethToken'),
                DistributionLimit: ethers.utils.parseEther('0.1'),
                DistributionLimitCurrency: getPlatformConstant('JBCurrencies_ETH'),
                OverflowAllowance: ethers.utils.parseEther('0.1'),
                OverflowAllowanceCurrency: getPlatformConstant('JBCurrencies_ETH')
            }, {

                Terminal: getContractRecord('JBDAIPaymentTerminal')['address'],
                Token: getPlatformConstant('usdToken'),
                DistributionLimit: ethers.utils.parseUnits('100', 18),
                DistributionLimitCurrency: getPlatformConstant('JBCurrencies_USD'),
                OverflowAllowance: 0,
                OverflowAllowanceCurrency: getPlatformConstant('JBCurrencies_USD')
            }
        ]
    };

    const ethFundingCycleInfo: FundingCycleInfo = {
        Duration: 60 * 24 * 7, // week in seconds
        DistributionLimit: ethers.utils.parseEther('0.1'),
        DistributionCurrency: getPlatformConstant('JBCurrencies_ETH'),
        TokenMintRate: hre.ethers.utils.parseUnits('1000000', 18), // 1M tokens/eth
        ReserveRate: 5000, // bps
        RedemptionRate: 5_000, // bps
        DiscountRate: 5_000_000, // 100% = 1_000_000_000
        ReconfigurationStrategy: ethers.constants.AddressZero,
        Ballot: ethers.constants.AddressZero,
        Payments: true, // inverse of pausePay
        Redemptions: true,
        Distribution: true,
        TokenMinting: false,
        TerminalConfiguration: true,
        ControllerConfiguration: true,
        TerminalMigration: true,
        ControllerMigration: true,
        FundingAccessConstraints: [
            {
                Terminal: getContractRecord('JBETHPaymentTerminal')['address'],
                Token: getPlatformConstant('ethToken'),
                DistributionLimit: ethers.utils.parseEther('0.1'),
                DistributionLimitCurrency: getPlatformConstant('JBCurrencies_ETH'),
                OverflowAllowance: ethers.utils.parseEther('0.1'),
                OverflowAllowanceCurrency: getPlatformConstant('JBCurrencies_ETH')
            }
        ]
    };

    let projectId = 5;
    // projectId = await deploySampleProject(dualFundingCycleInfo); // 5
    // await deploySampleProject(ethFundingCycleInfo); // 6
    // await configureSampleProject(projectId);
    // await deployPayers(projectId);
    // await deployNFTs();
    // await deployMixedPaymentSplitter(projectId);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/platform/samples.ts --network goerli
