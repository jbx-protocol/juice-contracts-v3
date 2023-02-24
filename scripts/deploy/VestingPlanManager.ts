import * as dotenv from "dotenv";
import { ethers } from 'hardhat';
import * as hre from 'hardhat';
import * as winston from 'winston';

import { deployRecordContract } from '../lib/lib';

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
                filename: 'log/deploy/VestingPlanManager.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying VestingPlanManager to ${hre.network.name}`);

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    deployRecordContract('VestingPlanManager', [deployer.address], deployer, 'VestingPlanManager', `./deployments/${hre.network.name}/extensions.json`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/VestingPlanManager.ts --network goerli
