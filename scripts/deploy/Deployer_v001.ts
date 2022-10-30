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
                filename: 'log/deploy/Deployer_v001.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v001 to ${hre.network.name}`);

    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    await deployRecordContract('NFTokenFactory', [], deployer, 'NFTokenFactory', deploymentLogPath);

    const nftokenFactoryAddress = getContractRecord('NFTokenFactory', deploymentLogPath).address;
    const deployerFactory = await ethers.getContractFactory('Deployer_v001', {
        libraries: { NFTokenFactory: nftokenFactoryAddress },
        signer: deployer
    });
    const deployerProxy = await upgrades.deployProxy(deployerFactory, { kind: 'uups', initializer: 'initialize' });
    await deployerProxy.deployed();

    // deployRecordContract('Deployer_v001', [], deployer, 'DeployerProxy', `./deployments/${hre.network.name}/extensions.json`, { NFTokenFactory: nfTokenFactoryLibrary.address }); // TODO: needs upgrade functionality

    logger.info(`deployed to ${deployerProxy.address} in ${deployerProxy.deployTransaction.hash}`);

    const deploymentLog = JSON.parse(fs.readFileSync(deploymentLogPath).toString());
    deploymentLog[hre.network.name]['DeployerProxy'] = {};
    deploymentLog[hre.network.name]['DeployerProxy']['address'] = deployerProxy.address;
    deploymentLog[hre.network.name]['DeployerProxy']['version'] = 1;
    deploymentLog[hre.network.name]['DeployerProxy']['abi'] = JSON.parse(deployerFactory.interface.format('json') as string);
    deploymentLog[hre.network.name]['DeployerProxy']['verified'] = false;
    fs.writeFileSync(deploymentLogPath, JSON.stringify(deploymentLog, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v001.ts --network goerli
