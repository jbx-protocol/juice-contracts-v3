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
                filename: 'log/deploy/Deployer_v003.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v003 to ${hre.network.name}`);

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const deploymentAddressLog = `./deployments/${hre.network.name}/extensions.json`;
    const deploymentAddresses = JSON.parse(fs.readFileSync(deploymentAddressLog).toString());

    const deployerProxyAddress = deploymentAddresses[hre.network.name]['DeployerProxy'];
    const nfTokenFactoryLibraryAddress = deploymentAddresses[hre.network.name]['NFTokenFactory'];
    const mixedPaymentSplitterFactoryLibraryAddress = deploymentAddresses[hre.network.name]['MixedPaymentSplitterFactory'];

    if (!deployerProxyAddress || deployerProxyAddress.length === 0) {
        logger.error(`could not find previous deployment of deployerProxy in ${deploymentAddressLog} under ['${hre.network.name}']['DeployerProxy']`);
        return;
    }

    if (!nfTokenFactoryLibraryAddress || nfTokenFactoryLibraryAddress.length === 0) {
        logger.error(`could not find previous deployment of NFTokenFactory in ${deploymentAddressLog} under ['${hre.network.name}']['NFTokenFactory']`);
        return;
    }

    if (!mixedPaymentSplitterFactoryLibraryAddress || mixedPaymentSplitterFactoryLibraryAddress.length === 0) {
        logger.error(`could not find previous deployment of MixedPaymentSplitterFactory in ${deploymentAddressLog} under ['${hre.network.name}']['MixedPaymentSplitterFactory']`);
        return;
    }

    logger.info(`found existing deployment of DeployerProxy at ${deployerProxyAddress}`);
    logger.info(`found existing deployment of NFTokenFactory at ${nfTokenFactoryLibraryAddress}`);
    logger.info(`found existing deployment of MixedPaymentSplitterFactory at ${mixedPaymentSplitterFactoryLibraryAddress}`);

    const auctionsFactoryFactory = await ethers.getContractFactory('AuctionsFactory', deployer);
    const auctionsFactoryFactoryLibrary = await auctionsFactoryFactory.connect(deployer).deploy();

    const deployerFactory = await ethers.getContractFactory('Deployer_v003', {
        libraries: {
            NFTokenFactory: nfTokenFactoryLibraryAddress,
            MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibraryAddress,
            AuctionsFactory: auctionsFactoryFactoryLibrary.address
        },
        signer: deployer
    });

    const dutchAuctionHouseFactory = await ethers.getContractFactory('DutchAuctionHouse', { signer: deployer });
    const sourceDutchAuctionHouse = await dutchAuctionHouseFactory.connect(deployer).deploy();
    await sourceDutchAuctionHouse.deployed();

    const englishAuctionHouseFactory = await ethers.getContractFactory('EnglishAuctionHouse', { signer: deployer });
    const sourceEnglishAuctionHouse = await englishAuctionHouseFactory.connect(deployer).deploy();
    await sourceEnglishAuctionHouse.deployed();

    const deployerProxy = await upgrades.upgradeProxy(deployerProxyAddress, deployerFactory, { kind: 'uups', call: { fn: 'initialize(address,address)', args: [sourceDutchAuctionHouse.address, sourceEnglishAuctionHouse.address] } });
    await deployerProxy.deployed();
    logger.info(`deployed to ${deployerProxy.address} in ${deployerProxy.deployTransaction.hash}`);

    deploymentAddresses[hre.network.name]['AuctionsFactory'] = auctionsFactoryFactoryLibrary.address;
    deploymentAddresses[hre.network.name]['DutchAuctionHouse'] = sourceDutchAuctionHouse.address;
    deploymentAddresses[hre.network.name]['EnglishAuctionHouse'] = sourceEnglishAuctionHouse.address;
    deploymentAddresses[hre.network.name]['DeployerProxyVersion'] = 3;
    fs.writeFileSync(deploymentAddressLog, JSON.stringify(deploymentAddresses, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v003.ts --network goerli
