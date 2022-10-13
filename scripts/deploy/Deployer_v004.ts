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
                filename: 'log/deploy/Deployer_v004.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v004 to ${hre.network.name}`);

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const deploymentAddressLog = `./deployments/${hre.network.name}/extensions.json`;
    const deploymentAddresses = JSON.parse(fs.readFileSync(deploymentAddressLog).toString());

    const deployerProxyAddress = deploymentAddresses[hre.network.name]['DeployerProxy'];
    const nfTokenFactoryLibraryAddress = deploymentAddresses[hre.network.name]['NFTokenFactory'];
    const mixedPaymentSplitterFactoryLibraryAddress = deploymentAddresses[hre.network.name]['MixedPaymentSplitterFactory'];
    const auctionsFactoryFactoryLibraryAddress = deploymentAddresses[hre.network.name]['AuctionsFactory'];
    const sourceDutchAuctionHouseAddress = deploymentAddresses[hre.network.name]['DutchAuctionHouse'];
    const sourceEnglishAuctionHouseAddress = deploymentAddresses[hre.network.name]['EnglishAuctionHouse'];


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

    if (!auctionsFactoryFactoryLibraryAddress || auctionsFactoryFactoryLibraryAddress.length === 0) {
        logger.error(`could not find previous deployment of AuctionsFactory in ${deploymentAddressLog} under ['${hre.network.name}']['AuctionsFactory']`);
        return;
    }

    if (!sourceDutchAuctionHouseAddress || sourceDutchAuctionHouseAddress.length === 0) {
        logger.error(`could not find previous deployment of DutchAuctionHouse in ${deploymentAddressLog} under ['${hre.network.name}']['DutchAuctionHouse']`);
        return;
    }

    if (!sourceEnglishAuctionHouseAddress || sourceEnglishAuctionHouseAddress.length === 0) {
        logger.error(`could not find previous deployment of EnglishAuctionHouse in ${deploymentAddressLog} under ['${hre.network.name}']['EnglishAuctionHouse']`);
        return;
    }

    logger.info(`found existing deployment of DeployerProxy at ${deployerProxyAddress}`);
    logger.info(`found existing deployment of NFTokenFactory at ${nfTokenFactoryLibraryAddress}`);
    logger.info(`found existing deployment of MixedPaymentSplitterFactory at ${mixedPaymentSplitterFactoryLibraryAddress}`);
    logger.info(`found existing deployment of AuctionsFactory at ${auctionsFactoryFactoryLibraryAddress}`);
    logger.info(`found existing deployment of DutchAuctionHouse at ${sourceDutchAuctionHouseAddress}`);
    logger.info(`found existing deployment of EnglishAuctionHouse at ${sourceEnglishAuctionHouseAddress}`);

    const nfuTokenFactoryFactory = await ethers.getContractFactory('NFUTokenFactory', deployer);
    const nfuTokenFactoryLibrary = await nfuTokenFactoryFactory.connect(deployer).deploy();

    const deployerFactory = await ethers.getContractFactory('Deployer_v004', {
        libraries: {
            NFTokenFactory: nfTokenFactoryLibraryAddress,
            MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibraryAddress,
            AuctionsFactory: auctionsFactoryFactoryLibraryAddress,
            NFUTokenFactory: nfuTokenFactoryLibrary.address
        },
        signer: deployer
    });

    const nfuTokenFactory = await ethers.getContractFactory('NFUToken', { signer: deployer });
    const nfuToken = await nfuTokenFactory.connect(deployer).deploy();
    await nfuToken.deployed();

    const deployerProxy = await upgrades.upgradeProxy(deployerProxyAddress, deployerFactory, { kind: 'uups', call: { fn: 'initialize(address,address,address)', args: [sourceDutchAuctionHouseAddress, sourceEnglishAuctionHouseAddress, nfuToken.address] } });
    await deployerProxy.deployed();
    logger.info(`deployed to ${deployerProxy.address} in ${deployerProxy.deployTransaction.hash}`);

    deploymentAddresses[hre.network.name]['NFUTokenFactory'] = nfuTokenFactoryLibrary.address;
    deploymentAddresses[hre.network.name]['NFUToken'] = nfuToken.address;
    deploymentAddresses[hre.network.name]['DeployerProxyVersion'] = 4;
    fs.writeFileSync(deploymentAddressLog, JSON.stringify(deploymentAddresses, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v004.ts --network goerli
