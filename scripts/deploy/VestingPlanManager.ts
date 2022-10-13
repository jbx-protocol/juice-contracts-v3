import * as dotenv from "dotenv";
import * as fs from 'fs';
import { ethers, upgrades } from 'hardhat';
import * as hre from 'hardhat';
import * as winston from 'winston';

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

    const vestingPlanManagerFactory = await ethers.getContractFactory('VestingPlanManager', deployer);
    const vestingPlanManager = await vestingPlanManagerFactory.connect(deployer).deploy();
    await vestingPlanManager.deployed();
    logger.info(`deployed to ${vestingPlanManager.address} in ${vestingPlanManager.deployTransaction.hash}`);

    const deploymentAddressLog = `./deployments/${hre.network.name}/extensions.json`;
    const deploymentAddresses = JSON.parse(fs.readFileSync(deploymentAddressLog).toString());
    deploymentAddresses[hre.network.name]['VestingPlanManager'] = vestingPlanManager.address;
    fs.writeFileSync(deploymentAddressLog, JSON.stringify(deploymentAddresses, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/VestingPlanManager.ts --network goerli
