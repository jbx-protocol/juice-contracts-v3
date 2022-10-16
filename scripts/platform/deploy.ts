import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import * as dotenv from "dotenv";
import * as fs from 'fs';
import { ethers, upgrades } from 'hardhat';
import * as hre from 'hardhat';
import * as winston from 'winston';

type DeployResult = {
    address: string,
    opHash: string
}

type DeployVerifyResult = {
    address: string,
    opHash: string,
    verified: boolean
}

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

async function deployContract(contractName: string, constructorArgs: any[], deployer: SignerWithAddress): Promise<DeployResult> {
    try {
        let message = `deploying ${contractName} as ${deployer.address}`;
        if (constructorArgs.length > 0) { message += ` with args: '${constructorArgs.join(',')}'`; }
        logger.info(message);

        const contractFactory = await ethers.getContractFactory(contractName, deployer);
        const contractInstance = await contractFactory.connect(deployer).deploy(...constructorArgs);
        await contractInstance.deployed();

        logger.info(`deployed to ${contractInstance.address} in ${contractInstance.deployTransaction.hash}`);

        return { address: '', opHash: '' };
    } catch (err) {
        logger.error(`failed to deploy ${contractName}`, err);
        throw err;
    }
}

async function deployVerifyContract(contractName: string, constructorArgs: any[], deployer: SignerWithAddress): Promise<DeployVerifyResult> {
    const deploymentResult = await deployContract(contractName, constructorArgs, deployer);

    try {
        await hre.run('verify:verify', { address: deploymentResult.address, constructorArguments: constructorArgs });

        return {
            address: deploymentResult.address,
            opHash: deploymentResult.opHash,
            verified: true
        }
    } catch (err) {
        logger.error(`failed to verify ${contractName}`, err);

        return {
            address: deploymentResult.address,
            opHash: deploymentResult.opHash,
            verified: false
        }
    }
}

async function deployVerifyRecordContract(contractName: string, constructorArgs: any[], deployer: SignerWithAddress) {
    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    let deploymentAddresses = JSON.parse(fs.readFileSync(deploymentLogPath).toString());

    if (deploymentAddresses[hre.network.name][contractName] !== undefined) {
        logger.info(`${contractName} already exists on ${hre.network.name} at ${deploymentAddresses[hre.network.name][contractName]['address']}`);
        return;
    }

    const deployVerifyResult = await deployVerifyContract(contractName, constructorArgs, deployer);

    deploymentAddresses[hre.network.name][contractName] = {
        address: deployVerifyResult.address,
        args: constructorArgs,
        abi: [],
        verified: deployVerifyResult.verified
    }

    fs.writeFileSync(deploymentLogPath, JSON.stringify(deploymentAddresses, undefined, 4))
}

function getContractRecord(contractName: string) {
    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    let deploymentAddresses = JSON.parse(fs.readFileSync(deploymentLogPath).toString());

    if (deploymentAddresses[hre.network.name][contractName] === undefined) {
        throw new Error(`no deployment record for ${contractName} on ${hre.network.name}`);
    }

    return deploymentAddresses[hre.network.name][contractName];
}

async function main() {
    dotenv.config();

    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    if (!fs.existsSync(deploymentLogPath)) {
        fs.writeFileSync(deploymentLogPath, '{}');
    }

    logger.info(`deploying DAOLABS Juicebox v3 fork to ${hre.network.name}`);

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    await deployVerifyRecordContract('JBETHERC20ProjectPayerDeployer', [], deployer);
    await deployVerifyRecordContract('JBETHERC20SplitsPayerDeployer', [], deployer);
    await deployVerifyRecordContract('JBOperatorStore', [], deployer);
    await deployVerifyRecordContract('JBPrices', [], deployer);
    await deployVerifyRecordContract('JBProjects', [], deployer);

    const transactionCount = await deployer.getTransactionCount();
    const expectedFundingCycleStoreAddress = ethers.utils.getContractAddress({ from: deployer.address, nonce: transactionCount + 1 });
    const jbOperatorStoreAddress = getContractRecord('JBOperatorStore').address;
    const jbProjectsAddress = getContractRecord('JBProjects').address;
    await deployVerifyRecordContract('JBDirectory', [jbOperatorStoreAddress, jbProjectsAddress, expectedFundingCycleStoreAddress, deployer.address], deployer);

    const jbDirectoryAddress = getContractRecord('JBDirectory').address;
    await deployVerifyRecordContract('JBFundingCycleStore', [jbDirectoryAddress], deployer);

    const jbFundingCycleStoreAddress = getContractRecord('JBFundingCycleStore').address;
    await deployVerifyRecordContract('JBTokenStore', [jbOperatorStoreAddress, jbProjectsAddress, jbDirectoryAddress, jbFundingCycleStoreAddress], deployer);

    await deployVerifyRecordContract('JBSplitsStore', [jbOperatorStoreAddress, jbProjectsAddress, jbDirectoryAddress], deployer);

    const jbTokenStoreAddress = getContractRecord('JBTokenStore').address;
    const jbSplitStoreAddress = getContractRecord('JBSplitsStore').address;
    await deployVerifyRecordContract('JBController', [jbOperatorStoreAddress, jbProjectsAddress, jbDirectoryAddress, jbFundingCycleStoreAddress, jbTokenStoreAddress, jbSplitStoreAddress], deployer);

    const jbPricesAddress = getContractRecord('JBPrices').address;
    await deployVerifyRecordContract('JBSingleTokenPaymentTerminalStore', [jbDirectoryAddress, jbFundingCycleStoreAddress, jbPricesAddress], deployer);

    await deployVerifyRecordContract('JBCurrencies', [], deployer);


}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/platform/deploy.ts --network goerli
