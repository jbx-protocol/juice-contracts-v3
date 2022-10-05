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
                filename: 'log/deploy/Deployer_v005.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying Deployer_v005 to ${hre.network.name}`);

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
    const nfuTokenFactoryLibraryAddress = deploymentAddresses[hre.network.name]['NFUTokenFactory'];
    const sourceNFUTokenAddress = deploymentAddresses[hre.network.name]['NFUToken'];

    const jbxDirectoryAddress = JSON.parse(fs.readFileSync(`./deployments/${hre.network.name}/JBDirectory.json`).toString())['address'];
    const jbxOperatorStoreAddress = JSON.parse(fs.readFileSync(`./deployments/${hre.network.name}/JBOperatorStore.json`).toString())['address'];
    const jbxProjectsAddress = JSON.parse(fs.readFileSync(`./deployments/${hre.network.name}/JBProjects.json`).toString())['address'];

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

    if (!nfuTokenFactoryLibraryAddress || nfuTokenFactoryLibraryAddress.length === 0) {
        logger.error(`could not find previous deployment of NFUTokenFactory in ${deploymentAddressLog} under ['${hre.network.name}']['NFUTokenFactory']`);
        return;
    }

    if (!jbxDirectoryAddress || jbxDirectoryAddress.length === 0) {
        logger.error(`could not find previous deployment of JBDirectory for '${hre.network.name}`);
        return;
    }

    if (!jbxOperatorStoreAddress || jbxOperatorStoreAddress.length === 0) {
        logger.error(`could not find previous deployment of JBOperator for '${hre.network.name}`);
        return;
    }

    if (!jbxProjectsAddress || jbxProjectsAddress.length === 0) {
        logger.error(`could not find previous deployment of NFUTokenFactory for '${hre.network.name}`);
        return;
    }

    logger.info(`found existing deployment of DeployerProxy at ${deployerProxyAddress}`);
    logger.info(`found existing deployment of NFTokenFactory at ${nfTokenFactoryLibraryAddress}`);
    logger.info(`found existing deployment of MixedPaymentSplitterFactory at ${mixedPaymentSplitterFactoryLibraryAddress}`);
    logger.info(`found existing deployment of AuctionsFactory at ${auctionsFactoryFactoryLibraryAddress}`);
    logger.info(`found existing deployment of DutchAuctionHouse at ${sourceDutchAuctionHouseAddress}`);
    logger.info(`found existing deployment of EnglishAuctionHouse at ${sourceEnglishAuctionHouseAddress}`);
    logger.info(`found existing deployment of NFUTokenFactory at ${nfuTokenFactoryLibraryAddress}`);
    logger.info(`found existing deployment of NFUToken at ${sourceNFUTokenAddress}`);
    logger.info(`found existing deployment of JBDirectory at ${jbxDirectoryAddress}`);
    logger.info(`found existing deployment of JBOperatorStore at ${jbxOperatorStoreAddress}`);
    logger.info(`found existing deployment of JBProjects at ${jbxProjectsAddress}`);

    const paymentProcessorFactory = await ethers.getContractFactory('PaymentProcessorFactory', deployer);
    const paymentProcessorFactoryLibrary = await paymentProcessorFactory.connect(deployer).deploy();

    const deployerFactory = await ethers.getContractFactory('Deployer_v005', {
        libraries: {
            NFTokenFactory: nfTokenFactoryLibraryAddress,
            MixedPaymentSplitterFactory: mixedPaymentSplitterFactoryLibraryAddress,
            AuctionsFactory: auctionsFactoryFactoryLibraryAddress,
            NFUTokenFactory: nfuTokenFactoryLibraryAddress,
            PaymentProcessorFactory: paymentProcessorFactoryLibrary.address
        },
        signer: deployer
    });

    const feeBps = 250;
    const uniswapPoolFee = 3000;
    const tokenLiquidatorFactory = await ethers.getContractFactory('TokenLiquidator', { signer: deployer });
    const tokenLiquidator = await tokenLiquidatorFactory.connect(deployer).deploy(jbxDirectoryAddress, jbxOperatorStoreAddress, jbxProjectsAddress, feeBps, uniswapPoolFee);
    await tokenLiquidator.deployed();

    const deployerProxy = await upgrades.upgradeProxy(deployerProxyAddress, deployerFactory, { kind: 'uups', call: { fn: 'initialize(address,address,address,address)', args: [sourceDutchAuctionHouseAddress, sourceEnglishAuctionHouseAddress, sourceNFUTokenAddress, tokenLiquidator.address] } });
    await deployerProxy.deployed();
    logger.info(`deployed to ${deployerProxy.address} in ${deployerProxy.deployTransaction.hash}`);

    deploymentAddresses[hre.network.name]['PaymentProcessorFactory'] = paymentProcessorFactoryLibrary.address;
    deploymentAddresses[hre.network.name]['TokenLiquidator'] = tokenLiquidator.address;
    deploymentAddresses[hre.network.name]['DeployerProxyVersion'] = 5;
    fs.writeFileSync(deploymentAddressLog, JSON.stringify(deploymentAddresses, undefined, 4));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/Deployer_v005.ts --network goerli
