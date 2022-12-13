import * as dotenv from "dotenv";
import * as fs from 'fs';
import { ethers, upgrades } from 'hardhat';
import * as hre from 'hardhat';
import * as winston from 'winston';

import { deployRecordContract, getContractRecord, verifyContract } from '../lib/lib';

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
                filename: 'log/deploy/Deployer_v003.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v003 to ${hre.network.name}`);

    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const deployerProxyAddress = getContractRecord('DeployerProxy', deploymentLogPath).address;
    const nftokenFactoryAddress = getContractRecord('NFTokenFactory', deploymentLogPath).address;
    const mixedPaymentSplitterFactoryAddress = getContractRecord('MixedPaymentSplitterFactory', deploymentLogPath).address;

    logger.info(`found existing deployment of DeployerProxy at ${deployerProxyAddress}`);
    logger.info(`found existing deployment of NFTokenFactory at ${nftokenFactoryAddress}`);
    logger.info(`found existing deployment of MixedPaymentSplitterFactory at ${mixedPaymentSplitterFactoryAddress}`);

    await deployRecordContract('AuctionsFactory', [], deployer, 'AuctionsFactory', deploymentLogPath);

    const auctionsFactoryAddress = getContractRecord('AuctionsFactory', deploymentLogPath).address;
    const deployerFactory = await ethers.getContractFactory('Deployer_v003', {
        libraries: {
            NFTokenFactory: nftokenFactoryAddress,
            MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryAddress,
            AuctionsFactory: auctionsFactoryAddress
        },
        signer: deployer
    });

    await deployRecordContract('DutchAuctionHouse', [], deployer, 'DutchAuctionHouse', deploymentLogPath);
    await deployRecordContract('EnglishAuctionHouse', [], deployer, 'EnglishAuctionHouse', deploymentLogPath);

    const sourceDutchAuctionHouseAddress = getContractRecord('DutchAuctionHouse', deploymentLogPath).address;
    const sourceEnglishAuctionHouseAddress = getContractRecord('EnglishAuctionHouse', deploymentLogPath).address;

    const deployerProxy = await upgrades.upgradeProxy(deployerProxyAddress, deployerFactory, { kind: 'uups', call: { fn: 'initialize(address,address)', args: [sourceDutchAuctionHouseAddress, sourceEnglishAuctionHouseAddress] } });
    logger.info(`waiting for ${deployerProxy.deployTransaction.hash}`);
    await deployerProxy.deployed();
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(deployerProxy.address);
    logger.info(`upgraded ${deployerProxy.address} to ${implementationAddress}`);

    await verifyContract('Deployer_v003', deployerProxy.address, []);

    const deploymentLog = JSON.parse(fs.readFileSync(deploymentLogPath).toString());
    deploymentLog[hre.network.name]['DeployerProxy']['version'] = 3;
    deploymentLog[hre.network.name]['DeployerProxy']['implementation'] = implementationAddress;
    deploymentLog[hre.network.name]['DeployerProxy']['abi'] = JSON.parse(deployerFactory.interface.format('json') as string);
    fs.writeFileSync(deploymentLogPath, JSON.stringify(deploymentLog, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v003.ts --network goerli
