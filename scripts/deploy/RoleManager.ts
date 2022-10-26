import * as dotenv from "dotenv";
import * as fs from 'fs';
import { ethers } from 'hardhat';
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
                filename: 'log/deploy/RoleManager.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying RoleManager to ${hre.network.name}`);

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const jbxDirectoryAddress = getContractRecord('JBController').address;
    const jbxOperatorStoreAddress = getContractRecord('JBController').address;
    const jbxProjectsAddress = getContractRecord('JBController').address;

    deployRecordContract('RoleManager', [jbxDirectoryAddress, jbxOperatorStoreAddress, jbxProjectsAddress, deployer.address], deployer, 'RoleManager', `./deployments/${hre.network.name}/extensions.json`)
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/RoleManager.ts --network goerli
