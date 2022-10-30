import * as dotenv from "dotenv";
import * as fs from 'fs';
import { ethers, upgrades } from 'hardhat';
import * as hre from 'hardhat';
import * as winston from 'winston';

import { deployRecordContract, getContractRecord } from '../lib/lib';

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
                filename: 'log/deploy/Deployer_v005.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v005 to ${hre.network.name}`);

    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const deployerProxyAddress = getContractRecord('DeployerProxy', deploymentLogPath).address;
    const nfTokenFactoryLibraryAddress = getContractRecord('NFTokenFactory', deploymentLogPath).address;
    const mixedPaymentSplitterFactoryLibraryAddress = getContractRecord('MixedPaymentSplitterFactory', deploymentLogPath).address;
    const auctionsFactoryFactoryLibraryAddress = getContractRecord('AuctionsFactory', deploymentLogPath).address;
    const sourceDutchAuctionHouseAddress = getContractRecord('DutchAuctionHouse', deploymentLogPath).address;
    const sourceEnglishAuctionHouseAddress = getContractRecord('EnglishAuctionHouse', deploymentLogPath).address;
    const nfuTokenFactoryLibraryAddress = getContractRecord('NFUTokenFactory', deploymentLogPath).address;
    const sourceNFUTokenAddress = getContractRecord('NFUToken', deploymentLogPath).address;

    const jbxDirectoryAddress = getContractRecord('JBDirectory').address;
    const jbxOperatorStoreAddress = getContractRecord('JBOperatorStore').address;
    const jbxProjectsAddress = getContractRecord('JBProjects').address;

    logger.info(`found existing deployment of DeployerProxy at ${deployerProxyAddress}`);
    logger.info(`found existing deployment of NFTokenFactory at ${nfTokenFactoryLibraryAddress}`);
    logger.info(`found existing deployment of MixedPaymentSplitterFactory at ${mixedPaymentSplitterFactoryLibraryAddress}`);
    logger.info(`found existing deployment of AuctionsFactory at ${auctionsFactoryFactoryLibraryAddress}`);
    logger.info(`found existing deployment of DutchAuctionHouse at ${sourceDutchAuctionHouseAddress}`);
    logger.info(`found existing deployment of EnglishAuctionHouse at ${sourceEnglishAuctionHouseAddress}`);
    logger.info(`found existing deployment of NFUTokenFactory at ${nfuTokenFactoryLibraryAddress}`);
    logger.info(`found existing deployment of NFUToken at ${sourceNFUTokenAddress}`);
    logger.info(`found existing deployment of JBDirectory at ${jbxDirectoryAddress}`);
    logger.info(`found existing deployment of JBOperatorStore at ${jbxOperatorStoreAddress}`);
    logger.info(`found existing deployment of JBProjects at ${jbxProjectsAddress}`);

    await deployRecordContract('PaymentProcessorFactory', [], deployer, 'PaymentProcessorFactory', deploymentLogPath);
    const paymentProcessorFactoryAddress = getContractRecord('PaymentProcessorFactory', deploymentLogPath).address;
    
    const deployerFactory = await ethers.getContractFactory('Deployer_v005', {
        libraries: {
            NFTokenFactory: nfTokenFactoryLibraryAddress,
            MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibraryAddress,
            AuctionsFactory: auctionsFactoryFactoryLibraryAddress,
            NFUTokenFactory: nfuTokenFactoryLibraryAddress,
            PaymentProcessorFactory: paymentProcessorFactoryAddress
        },
        signer: deployer
    });

    const feeBps = 250;
    const uniswapPoolFee = 3000;

    await deployRecordContract('TokenLiquidator', [jbxDirectoryAddress, jbxOperatorStoreAddress, jbxProjectsAddress, feeBps, uniswapPoolFee], deployer, 'TokenLiquidator', deploymentLogPath);
    const tokenLiquidatorAddress = getContractRecord('TokenLiquidator', deploymentLogPath).address;

    const deployerProxy = await upgrades.upgradeProxy(deployerProxyAddress, deployerFactory, { kind: 'uups', call: { fn: 'initialize(address,address,address,address)', args: [sourceDutchAuctionHouseAddress, sourceEnglishAuctionHouseAddress, sourceNFUTokenAddress, tokenLiquidatorAddress] } });
    await deployerProxy.deployed();
    logger.info(`upgraded ${deployerProxy.address} in ${deployerProxy.deployTransaction.hash}`);

    const deploymentLog = JSON.parse(fs.readFileSync(deploymentLogPath).toString());
    deploymentLog[hre.network.name]['DeployerProxy']['version'] = 5;
    deploymentLog[hre.network.name]['DeployerProxy']['abi'] = JSON.parse(deployerFactory.interface.format('json') as string);
    fs.writeFileSync(deploymentLogPath, JSON.stringify(deploymentLog, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v005.ts --network goerli
