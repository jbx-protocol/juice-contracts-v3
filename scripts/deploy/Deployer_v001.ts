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
                filename: 'log/deploy/Deployer_v001.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v001 to ${hre.network.name}`);

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const nfTokenFactoryFactory = await ethers.getContractFactory('NFTokenFactory', deployer);
    const nfTokenFactoryLibrary = await nfTokenFactoryFactory.connect(deployer).deploy();

    const deployerFactory = await ethers.getContractFactory('Deployer_v001', {
        libraries: { NFTokenFactory: nfTokenFactoryLibrary.address },
        signer: deployer
    });
    const deployerProxy = await upgrades.deployProxy(deployerFactory, { kind: 'uups', initializer: 'initialize' });
    await deployerProxy.deployed();
    logger.info(`deployed to ${deployerProxy.address} in ${deployerProxy.deployTransaction.hash}`);

    const deploymentAddressLog = `./deployments/${hre.network.name}/extensions.json`;
    const deploymentAddresses = JSON.parse(fs.readFileSync(deploymentAddressLog).toString());
    deploymentAddresses[hre.network.name]['NFTokenFactory'] = nfTokenFactoryLibrary.address;
    deploymentAddresses[hre.network.name]['DeployerProxy'] = deployerProxy.address;
    deploymentAddresses[hre.network.name]['DeployerProxyVersion'] = 1;
    fs.writeFileSync(deploymentAddressLog, JSON.stringify(deploymentAddresses, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v001.ts --network goerli
