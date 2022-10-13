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
                filename: 'log/deploy/Deployer_v002.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v002 to ${hre.network.name}`);

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const deploymentAddressLog = `./deployments/${hre.network.name}/extensions.json`;
    const deploymentAddresses = JSON.parse(fs.readFileSync(deploymentAddressLog).toString());

    let deployerProxyAddress = deploymentAddresses[hre.network.name]['DeployerProxy'];
    let nfTokenFactoryLibraryAddress = deploymentAddresses[hre.network.name]['NFTokenFactory'];

    if (!deployerProxyAddress || deployerProxyAddress.length === 0) {
        logger.error(`could not find previous deployment of deployerProxy in ${deploymentAddressLog} under ['${hre.network.name}']['DeployerProxy']`);
        return;
    }

    if (!nfTokenFactoryLibraryAddress || nfTokenFactoryLibraryAddress.length === 0) {
        logger.error(`could not find previous deployment of NFTokenFactory in ${deploymentAddressLog} under ['${hre.network.name}']['NFTokenFactory']`);
        return;
    }

    logger.info(`found existing deployment of DeployerProxy at ${deployerProxyAddress}`);
    logger.info(`found existing deployment of NFTokenFactory at ${nfTokenFactoryLibraryAddress}`);

    const mixedPaymentSplitterFactoryFactory = await ethers.getContractFactory('MixedPaymentSplitterFactory', deployer);
    const mixedPaymentSplitterFactoryLibrary = await mixedPaymentSplitterFactoryFactory.connect(deployer).deploy();

    const deployerFactory = await ethers.getContractFactory('Deployer_v002', {
        libraries: {
            NFTokenFactory: nfTokenFactoryLibraryAddress,
            MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibrary.address
        },
        signer: deployer
    });

    const deployerProxy = await upgrades.upgradeProxy(deployerProxyAddress, deployerFactory, { kind: 'uups', call: { fn: 'initialize' } });
    await deployerProxy.deployed();
    logger.info(`deployed to ${deployerProxy.address} in ${deployerProxy.deployTransaction.hash}`);

    deploymentAddresses[hre.network.name]['MixedPaymentSplitterFactory'] = mixedPaymentSplitterFactoryLibrary.address;
    deploymentAddresses[hre.network.name]['DeployerProxyVersion'] = 2;
    fs.writeFileSync(deploymentAddressLog, JSON.stringify(deploymentAddresses, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v002.ts --network goerli
