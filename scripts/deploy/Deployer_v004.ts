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
                filename: 'log/deploy/Deployer_v004.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v004 to ${hre.network.name}`);

    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const deployerProxyAddress = getContractRecord('DeployerProxy', deploymentLogPath).address;
    const nftokenFactoryAddress = getContractRecord('NFTokenFactory', deploymentLogPath).address;
    const mixedPaymentSplitterFactoryAddress = getContractRecord('MixedPaymentSplitterFactory', deploymentLogPath).address;
    const auctionsFactoryAddress = getContractRecord('AuctionsFactory', deploymentLogPath).address;
    const sourceDutchAuctionHouseAddress = getContractRecord('DutchAuctionHouse', deploymentLogPath).address;
    const sourceEnglishAuctionHouseAddress = getContractRecord('EnglishAuctionHouse', deploymentLogPath).address;
    const sourceFixedPriceSaleAddress = getContractRecord('FixedPriceSale', deploymentLogPath).address;

    logger.info(`found existing deployment of DeployerProxy at ${deployerProxyAddress}`);
    logger.info(`found existing deployment of NFTokenFactory at ${nftokenFactoryAddress}`);
    logger.info(`found existing deployment of MixedPaymentSplitterFactory at ${mixedPaymentSplitterFactoryAddress}`);
    logger.info(`found existing deployment of AuctionsFactory at ${auctionsFactoryAddress}`);
    logger.info(`found existing deployment of DutchAuctionHouse at ${sourceDutchAuctionHouseAddress}`);
    logger.info(`found existing deployment of EnglishAuctionHouse at ${sourceEnglishAuctionHouseAddress}`);
    logger.info(`found existing deployment of FixedPriceSale at ${sourceFixedPriceSaleAddress}`);

    await deployRecordContract('NFUTokenFactory', [], deployer, 'NFUTokenFactory', deploymentLogPath);

    const nfutokenFactoryAddress = getContractRecord('NFUTokenFactory', deploymentLogPath).address;
    const deployerFactory = await ethers.getContractFactory('Deployer_v004', {
        libraries: {
            NFTokenFactory: nftokenFactoryAddress,
            MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryAddress,
            AuctionsFactory: auctionsFactoryAddress,
            NFUTokenFactory: nfutokenFactoryAddress
        },
        signer: deployer
    });

    await deployRecordContract('NFUToken', [], deployer, 'NFUToken', deploymentLogPath);

    const sourceNFUTokenRecord = getContractRecord('NFUToken', deploymentLogPath);
    await verifyRecordContract('NFUToken', sourceNFUTokenRecord.address, sourceNFUTokenRecord.args, deploymentLogPath);

    const deployerProxy = await upgrades.upgradeProxy(deployerProxyAddress, deployerFactory,
        {
            kind: 'uups',
            call: {
                fn: 'initialize(address,address,address,address)',
                args: [sourceDutchAuctionHouseAddress, sourceEnglishAuctionHouseAddress, sourceFixedPriceSaleAddress, sourceNFUTokenRecord.address]
            }
        });
    logger.info(`waiting for ${deployerProxy.deployTransaction.hash}`);
    await deployerProxy.deployed();
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(deployerProxy.address);
    logger.info(`upgraded ${deployerProxy.address} to ${implementationAddress}`);

    await verifyContract('Deployer_v004', deployerProxy.address, []);

    const deploymentLog = JSON.parse(fs.readFileSync(deploymentLogPath).toString());
    deploymentLog[hre.network.name]['DeployerProxy']['version'] = 4;
    deploymentLog[hre.network.name]['DeployerProxy']['implementation'] = implementationAddress;
    deploymentLog[hre.network.name]['DeployerProxy']['abi'] = JSON.parse(deployerFactory.interface.format('json') as string);
    fs.writeFileSync(deploymentLogPath, JSON.stringify(deploymentLog, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v004.ts --network goerli
