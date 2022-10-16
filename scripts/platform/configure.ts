import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";
import * as hre from 'hardhat';
import * as winston from 'winston';

import { deployRecordContract, getContractRecord, getPlatformConstant } from './deploy';

const logger = winston.createLogger({
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.printf(info => { return `${info.timestamp}|${info.level}|${info.message}`; })
    ),
    transports: [
        new winston.transports.Console({
            level: 'info'
        }),
        new winston.transports.File({
            level: 'debug',
            filename: 'log/deploy/platform.log',
            handleExceptions: true,
            maxsize: (5 * 1024 * 1024), // 5 mb
            maxFiles: 5
        })
    ]
});

async function miscConfiguration(deployer: SignerWithAddress) {
    const jbDirectoryRecord = getContractRecord('JBDirectory');
    const jbControllerRecord = getContractRecord('JBController');

    const jbDirectoryContract = await hre.ethers.getContractAt(jbDirectoryRecord['abi'], jbDirectoryRecord['address'], deployer);

    const isAllowedToSetFirstController = await jbDirectoryContract.connect(deployer)['isAllowedToSetFirstController(address)'](jbControllerRecord['address']);

    if (!isAllowedToSetFirstController) {
        const tx = await jbDirectoryContract.connect(deployer)['setIsAllowedToSetFirstController(address,bool)'](jbControllerRecord['address'], true);
        await tx.wait();

        logger.info(`set setIsAllowedToSetFirstController on JBDirectory at ${jbDirectoryRecord['address']} to true`);
    } else {
        logger.info(`setIsAllowedToSetFirstController on JBDirectory at ${jbDirectoryRecord['address']} already configured`);
    }
}

async function configureEtherPriceFeed(deployer: SignerWithAddress) {
    const jbPriceRecord = getContractRecord('JBPrices');
    const jbPricesContract = await hre.ethers.getContractAt(jbPriceRecord['abi'], jbPriceRecord['address'], deployer);
    const jbCurrencies_ETH = getPlatformConstant('JBCurrencies_ETH');
    const jbCurrencies_USD = getPlatformConstant('JBCurrencies_USD');

    const chainlinkV2UsdEthPriceFeed = getPlatformConstant('chainlinkV2UsdEthPriceFeed');
    if (chainlinkV2UsdEthPriceFeed === undefined) {
        logger.error(`Chainlink USD/ETH price feed not specified`);
        return;
    }

    const usdEthFeedAddress = await jbPricesContract.connect(deployer)['feedFor(uint256,uint256)'](jbCurrencies_USD, jbCurrencies_ETH);
    if (usdEthFeedAddress !== hre.ethers.constants.AddressZero) {
        logger.info(`Chainlink USD/ETH price feed already set on JBPrices at ${jbPriceRecord['address']}`);
        return;
    }

    await deployRecordContract('JBChainlinkV3PriceFeed', [chainlinkV2UsdEthPriceFeed], deployer);

    const priceFeedAddress = getContractRecord('JBChainlinkV3PriceFeed').address;
    await jbPricesContract.connect(deployer)['addFeedFor(uint256,uint256,address)'](jbCurrencies_USD, jbCurrencies_ETH, priceFeedAddress);

    logger.info(`set Chainlink USD/ETH price feed on JBPrices at ${jbPriceRecord['address']} to ${priceFeedAddress}`);
}

async function transferOwnership(deployer: SignerWithAddress) {
    let platformOwnerAddress: any;
    try {
        platformOwnerAddress = getPlatformConstant('platformOwner');
    } catch {
        logger.info(`Platform owner not specified`);
        return;
    }

    const jbPriceRecord = getContractRecord('JBPrices');
    const jbPricesContract = await hre.ethers.getContractAt(jbPriceRecord['abi'], jbPriceRecord['address'], deployer);
    if ((await jbPricesContract['owner()']) != platformOwnerAddress) {
        const tx = await jbPricesContract.connect(deployer)['transferOwnership(address)'](platformOwnerAddress);
        await tx.wait();
        logger.info(`transferred ownership of JBPrices at ${jbPriceRecord['address']} to ${platformOwnerAddress}`);
    }

    const jbDirectoryRecord = getContractRecord('JBDirectory');
    const jbDirectoryContract = await hre.ethers.getContractAt(jbDirectoryRecord['abi'], jbDirectoryRecord['address'], deployer);
    if ((await jbDirectoryContract.connect(deployer)['owner()']) != platformOwnerAddress) {
        let tx = await jbDirectoryContract.connect(deployer)['transferOwnership(address)'](platformOwnerAddress);
        await tx.wait();
        logger.info(`transferred ownership of JBDirectory at ${jbDirectoryRecord['address']} to ${platformOwnerAddress}`);
    }
}

async function deployParentProject(deployer: SignerWithAddress) {
    const jbProjectsRecord = getContractRecord('JBProjects');
    const jbProjectsContract = await hre.ethers.getContractAt(jbProjectsRecord['abi'], jbProjectsRecord['address'], deployer);

    if ((await jbProjectsContract['count()']() as BigNumber).toNumber() === 0) {
        logger.info('launching parent project');

        const beneficiaries = [];
        let primaryBeneficiary = getPlatformConstant('primaryBeneficiary', deployer.address);

        let splits = [];

        beneficiaries.map((beneficiary) => {
            splits.push({
                preferClaimed: false,
                preferAddToBalance: false,
                percent: Math.floor((1000000000 - 300600000) / beneficiaries.length),
                projectId: 0,
                beneficiary: beneficiary,
                lockedUntil: 0,
                allocator: hre.ethers.constants.AddressZero,
            });
        });

        splits.push({
            preferClaimed: false,
            preferAddToBalance: false,
            percent: 300600000,
            projectId: 0,
            beneficiary: primaryBeneficiary,
            lockedUntil: 0,
            allocator: hre.ethers.constants.AddressZero,
        });

        const groupedSplits = [{ group: 2, splits }];

        const jb3DayReconfigurationBufferBallotRecord = getContractRecord('JB3DayReconfigurationBufferBallot');
        const jbETHPaymentTerminalRecord = getContractRecord('JBETHPaymentTerminal');
        const jbControllerRecord = getContractRecord('JBController');
        const jbControllerContract = await hre.ethers.getContractAt(jbControllerRecord['abi'], jbControllerRecord['address'], deployer);
        const platformOwnerAddress = getPlatformConstant('platformOwner', deployer.address);

        const domain = 0;
        const projectMetadataCID = ''
        const projectMetadata = [projectMetadataCID, domain];

        const protocolLaunchDate = getPlatformConstant('protocolLaunchDate', Math.floor(Date.now() / 1000) - 10);

        const duration = 1209600;
        const weight = hre.ethers.BigNumber.from('62850518250000000000000');
        const discountRate = 5000000;
        const ballot = jb3DayReconfigurationBufferBallotRecord['address'];
        const fundingCycleData = [duration, weight, discountRate, ballot];

        const allowSetTerminals = false;
        const allowSetController = true;
        const pauseTransfer = true;
        const global = [allowSetTerminals, allowSetController, pauseTransfer];

        const reservedRate = 5000;
        const redemptionRate = 0;
        const ballotRedemptionRate = 0;
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

        const fundAccessConstraints = [];

        const terminals = [jbETHPaymentTerminalRecord['address']];

        const tx = await jbControllerContract.connect(deployer)['launchProjectFor(address,(string,uint256),(uint256,uint256,uint256,address),((bool,bool,bool),uint256,uint256,uint256,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,bool,address,uint256),uint256,(uint256,(bool,bool,uint256,uint256,address,uint256,address)[])[],(address,address,uint256,uint256,uint256,uint256)[],address[],string)'](
            platformOwnerAddress,
            projectMetadata,
            fundingCycleData,
            fundingCycleMetadata,
            protocolLaunchDate,
            groupedSplits,
            fundAccessConstraints,
            terminals,
            ''
        );
        await tx.wait();
        logger.info('launched parent project');
    } else {
        logger.info('parent project appears to exist');
    }
}

async function main() {
    logger.info(`configuring DAOLABS Juicebox v3 fork on ${hre.network.name}`);

    const [deployer] = await hre.ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    await miscConfiguration(deployer);
    await configureEtherPriceFeed(deployer);
    await transferOwnership(deployer);
    await deployParentProject(deployer);

    logger.info('configuration complete');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/platform/configure.ts --network goerli
