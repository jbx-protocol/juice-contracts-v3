import * as dotenv from "dotenv";
import * as fs from 'fs';
import { ethers, upgrades } from 'hardhat';
import * as hre from 'hardhat';
import * as winston from 'winston';

import { deployRecordContract, getContractRecord, verifyContract, verifyRecordContract } from '../lib/lib';

async function main() {
    dotenv.config();

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
                filename: 'log/deploy/Deployer_v007.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v007 to ${hre.network.name}`);

    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const deployerProxyAddress = getContractRecord('DeployerProxy', deploymentLogPath).address;
    const nfTokenFactoryLibraryAddress = getContractRecord('NFTokenFactory', deploymentLogPath).address;
    const mixedPaymentSplitterFactoryLibraryAddress = getContractRecord('MixedPaymentSplitterFactory', deploymentLogPath).address;
    const auctionsFactoryFactoryLibraryAddress = getContractRecord('AuctionsFactory', deploymentLogPath).address;
    const sourceDutchAuctionHouseAddress = getContractRecord('DutchAuctionHouse', deploymentLogPath).address;
    const sourceEnglishAuctionHouseAddress = getContractRecord('EnglishAuctionHouse', deploymentLogPath).address;
    const sourceFixedPriceSaleAddress = getContractRecord('FixedPriceSale', deploymentLogPath).address;
    const nfuTokenFactoryLibraryAddress = getContractRecord('NFUTokenFactory', deploymentLogPath).address;
    const sourceNFUTokenAddress = getContractRecord('NFUToken', deploymentLogPath).address;
    const paymentProcessorFactoryLibraryAddress = getContractRecord('PaymentProcessorFactory', deploymentLogPath).address;
    const sourceTokenLiquidatorAddress = getContractRecord('TokenLiquidator', deploymentLogPath).address;
    const nftRewardDataSourceFactoryAddress = getContractRecord('NFTRewardDataSourceFactory', deploymentLogPath).address;

    const jbxDirectoryAddress = getContractRecord('JBDirectory').address;
    const jbxOperatorStoreAddress = getContractRecord('JBOperatorStore').address;
    const jbxProjectsAddress = getContractRecord('JBProjects').address;

    logger.info(`found existing deployment of DeployerProxy at ${deployerProxyAddress}`);
    logger.info(`found existing deployment of NFTokenFactory at ${nfTokenFactoryLibraryAddress}`);
    logger.info(`found existing deployment of MixedPaymentSplitterFactory at ${mixedPaymentSplitterFactoryLibraryAddress}`);
    logger.info(`found existing deployment of AuctionsFactory at ${auctionsFactoryFactoryLibraryAddress}`);
    logger.info(`found existing deployment of DutchAuctionHouse at ${sourceDutchAuctionHouseAddress}`);
    logger.info(`found existing deployment of EnglishAuctionHouse at ${sourceEnglishAuctionHouseAddress}`);
    logger.info(`found existing deployment of FixedPriceSale at ${sourceFixedPriceSaleAddress}`);
    logger.info(`found existing deployment of NFUTokenFactory at ${nfuTokenFactoryLibraryAddress}`);
    logger.info(`found existing deployment of NFUToken at ${sourceNFUTokenAddress}`);
    logger.info(`found existing deployment of PaymentProcessorFactory at ${paymentProcessorFactoryLibraryAddress}`);
    logger.info(`found existing deployment of TokenLiquidator at ${sourceTokenLiquidatorAddress}`);
    logger.info(`found existing deployment of NFTRewardDataSourceFactory at ${nftRewardDataSourceFactoryAddress}`);
    logger.info(`found existing deployment of JBDirectory at ${jbxDirectoryAddress}`);
    logger.info(`found existing deployment of JBOperatorStore at ${jbxOperatorStoreAddress}`);
    logger.info(`found existing deployment of JBProjects at ${jbxProjectsAddress}`);

    await deployRecordContract('TraitTokenFactory', [], deployer, 'TraitTokenFactory', deploymentLogPath);
    const traitTokenFactoryAddress = getContractRecord('TraitTokenFactory', deploymentLogPath).address;

    await deployRecordContract('AuctionMachineFactory', [], deployer, 'AuctionMachineFactory', deploymentLogPath);
    const auctionMachineFactoryAddress = getContractRecord('AuctionMachineFactory', deploymentLogPath).address;

    await deployRecordContract('NFUEditionFactory', [], deployer, 'NFUEditionFactory', deploymentLogPath);
    const nfuEditionFactoryAddress = getContractRecord('NFUEditionFactory', deploymentLogPath).address;

    const deployerFactory = await ethers.getContractFactory('Deployer_v007', {
        libraries: {
            NFTokenFactory: nfTokenFactoryLibraryAddress,
            MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibraryAddress,
            AuctionsFactory: auctionsFactoryFactoryLibraryAddress,
            NFUTokenFactory: nfuTokenFactoryLibraryAddress,
            PaymentProcessorFactory: paymentProcessorFactoryLibraryAddress,
            NFTRewardDataSourceFactory: nftRewardDataSourceFactoryAddress,
            TraitTokenFactory: traitTokenFactoryAddress,
            AuctionMachineFactory: auctionMachineFactoryAddress,
            NFUEditionFactory: nfuEditionFactoryAddress
        },
        signer: deployer
    });

    await deployRecordContract('DutchAuctionMachine', [], deployer, 'DutchAuctionMachine', deploymentLogPath);
    await deployRecordContract('EnglishAuctionMachine', [], deployer, 'EnglishAuctionMachine', deploymentLogPath);
    await deployRecordContract('TraitToken', [], deployer, 'TraitToken', deploymentLogPath);
    await deployRecordContract('NFUEdition', [], deployer, 'NFUEdition', deploymentLogPath);

    const dutchAuctionMachineAddress = getContractRecord('DutchAuctionMachine', deploymentLogPath).address;
    const englishAuctionMachineAddress = getContractRecord('EnglishAuctionMachine', deploymentLogPath).address;
    const sourceTraitTokenRecord = getContractRecord('TraitToken', deploymentLogPath);
    const sourceNFUEditionRecord = getContractRecord('NFUEdition', deploymentLogPath);

    const deployerProxy = await upgrades.upgradeProxy(deployerProxyAddress, deployerFactory, {
        kind: 'uups',
        call: {
            fn: 'initialize(address,address,address,address,address,address,address,address,address)',
            args: [
                sourceDutchAuctionHouseAddress,
                sourceEnglishAuctionHouseAddress,
                sourceFixedPriceSaleAddress,
                sourceNFUTokenAddress,
                sourceTokenLiquidatorAddress,
                dutchAuctionMachineAddress,
                englishAuctionMachineAddress,
                sourceTraitTokenRecord.address,
                sourceNFUEditionRecord.address]
        }
    });
    logger.info(`waiting for ${deployerProxy.deployTransaction.hash}`);
    await deployerProxy.deployed();
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(deployerProxy.address);
    logger.info(`upgraded ${deployerProxy.address} to ${implementationAddress}`);

    await verifyContract('Deployer_v007', deployerProxy.address, []);

    const deploymentLog = JSON.parse(fs.readFileSync(deploymentLogPath).toString());
    deploymentLog[hre.network.name]['DeployerProxy']['version'] = 7;
    deploymentLog[hre.network.name]['DeployerProxy']['implementation'] = implementationAddress;
    deploymentLog[hre.network.name]['DeployerProxy']['abi'] = JSON.parse(deployerFactory.interface.format('json') as string);
    fs.writeFileSync(deploymentLogPath, JSON.stringify(deploymentLog, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v007.ts --network goerli
