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
                filename: 'log/deploy/Deployer_v002.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v002 to ${hre.network.name}`);

    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const deployerProxyAddress = getContractRecord('DeployerProxy', deploymentLogPath).address;
    const nftokenFactoryAddress = getContractRecord('NFTokenFactory', deploymentLogPath).address;

    logger.info(`found existing deployment of DeployerProxy at ${deployerProxyAddress}`);
    logger.info(`found existing deployment of NFTokenFactory at ${nftokenFactoryAddress}`);

    await deployRecordContract('MixedPaymentSplitterFactory', [], deployer, 'MixedPaymentSplitterFactory', deploymentLogPath);

    const mixedPaymentSplitterFactoryAddress = getContractRecord('MixedPaymentSplitterFactory', deploymentLogPath).address;
    const deployerFactory = await ethers.getContractFactory('Deployer_v002', {
        libraries: {
            NFTokenFactory: nftokenFactoryAddress,
            MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryAddress
        },
        signer: deployer
    });

    const deployerProxy = await upgrades.upgradeProxy(deployerProxyAddress, deployerFactory, { kind: 'uups', call: { fn: 'initialize' } });
    logger.info(`waiting for ${deployerProxy.deployTransaction.hash}`);
    await deployerProxy.deployed();
    logger.info(`upgraded ${deployerProxy.address}`);

    const deploymentLog = JSON.parse(fs.readFileSync(deploymentLogPath).toString());
    deploymentLog[hre.network.name]['DeployerProxy']['version'] = 2;
    deploymentLog[hre.network.name]['DeployerProxy']['abi'] = JSON.parse(deployerFactory.interface.format('json') as string);
    fs.writeFileSync(deploymentLogPath, JSON.stringify(deploymentLog, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v002.ts --network goerli
