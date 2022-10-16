import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import * as dotenv from "dotenv";
import * as fs from 'fs';
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

        const contractFactory = await hre.ethers.getContractFactory(contractName, deployer);
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

async function deployVerifyRecordContract(contractName: string, constructorArgs: any[], deployer: SignerWithAddress, recordAs?: string) {
    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    let deploymentAddresses = JSON.parse(fs.readFileSync(deploymentLogPath).toString());

    if (deploymentAddresses[hre.network.name][contractName] !== undefined) {
        logger.info(`${contractName} already exists on ${hre.network.name} at ${deploymentAddresses[hre.network.name][contractName]['address']}`);
        return;
    }

    const deployVerifyResult = await deployVerifyContract(contractName, constructorArgs, deployer);

    if (recordAs !== undefined) {
        deploymentAddresses[hre.network.name][recordAs] = {
            address: deployVerifyResult.address,
            type: contractName,
            args: constructorArgs,
            abi: [], // TODO
            verified: deployVerifyResult.verified
        }
    } else {
        deploymentAddresses[hre.network.name][contractName] = {
            address: deployVerifyResult.address,
            args: constructorArgs,
            abi: [], // TODO
            verified: deployVerifyResult.verified
        }
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

function getConstant(valueName: string) {
    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    let deploymentAddresses = JSON.parse(fs.readFileSync(deploymentLogPath).toString());

    if (deploymentAddresses[hre.network.name][valueName] === undefined) {
        throw new Error(`no constant value for ${valueName} on ${hre.network.name}`);
    }

    return deploymentAddresses[hre.network.name]['constants'][valueName];
}

async function main() {
    dotenv.config();

    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    if (!fs.existsSync(deploymentLogPath)) {
        fs.writeFileSync(deploymentLogPath, '{}');
    }

    logger.info(`deploying DAOLABS Juicebox v3 fork to ${hre.network.name}`);

    const [deployer] = await hre.ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    await deployVerifyRecordContract('JBETHERC20ProjectPayerDeployer', [], deployer);
    await deployVerifyRecordContract('JBETHERC20SplitsPayerDeployer', [], deployer);
    await deployVerifyRecordContract('JBOperatorStore', [], deployer);
    await deployVerifyRecordContract('JBPrices', [], deployer);
    await deployVerifyRecordContract('JBProjects', [], deployer);

    const transactionCount = await deployer.getTransactionCount();
    const expectedFundingCycleStoreAddress = hre.ethers.utils.getContractAddress({ from: deployer.address, nonce: transactionCount + 1 });
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

    const jbCurrencies_ETH = getConstant['JBCurrencies_ETH'];
    const jbSingleTokenPaymentTerminalStoreAddress = getContractRecord('JBSingleTokenPaymentTerminalStore').address;
    await deployVerifyRecordContract('JBETHPaymentTerminal', [jbCurrencies_ETH, jbOperatorStoreAddress, jbProjectsAddress, jbDirectoryAddress, jbSplitStoreAddress, jbPricesAddress, jbSingleTokenPaymentTerminalStoreAddress,
        deployer.address], deployer);

    const daySeconds = 60 * 60 * 24;
    await deployVerifyRecordContract('JBReconfigurationBufferBallot', [daySeconds], deployer, 'JB1DayReconfigurationBufferBallot');
    await deployVerifyRecordContract('JBReconfigurationBufferBallot', [daySeconds * 3], deployer, 'JB3DayReconfigurationBufferBallot');
    await deployVerifyRecordContract('JBReconfigurationBufferBallot', [daySeconds * 7], deployer, 'JB7DayReconfigurationBufferBallot');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/platform/deploy.ts --network goerli
