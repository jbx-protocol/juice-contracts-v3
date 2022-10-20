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

    const jbxDirectoryAddress = JSON.parse(fs.readFileSync(`./deployments/${hre.network.name}/JBDirectory.json`).toString())['address'];
    const jbxOperatorStoreAddress = JSON.parse(fs.readFileSync(`./deployments/${hre.network.name}/JBOperatorStore.json`).toString())['address'];
    const jbxProjectsAddress = JSON.parse(fs.readFileSync(`./deployments/${hre.network.name}/JBProjects.json`).toString())['address'];

    const RoleManagerFactory = await ethers.getContractFactory('RoleManager', deployer);
    const RoleManager = await RoleManagerFactory.connect(deployer).deploy(jbxDirectoryAddress, jbxOperatorStoreAddress, jbxProjectsAddress, deployer.address);
    await RoleManager.deployed();
    logger.info(`deployed to ${RoleManager.address} in ${RoleManager.deployTransaction.hash}`);

    try {
        logger.info(`verifying RoleManager at ${RoleManager.address} with Etherscan`);
        await hre.run('verify:verify', { address: RoleManager.address, constructorArguments: [jbxDirectoryAddress, jbxOperatorStoreAddress, jbxProjectsAddress, deployer.address] });
        logger.info('verification complete');

    } catch (err) {
        logger.error(`failed to verify ${RoleManager.address} with Etherscan`, err);
    }

    const deploymentAddressLog = `./deployments/${hre.network.name}/extensions.json`;
    const deploymentAddresses = JSON.parse(fs.readFileSync(deploymentAddressLog).toString());
    deploymentAddresses[hre.network.name]['RoleManager'] = RoleManager.address;
    fs.writeFileSync(deploymentAddressLog, JSON.stringify(deploymentAddresses, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/RoleManager.ts --network goerli
