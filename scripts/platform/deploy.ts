import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import * as fs from 'fs';
import * as hre from 'hardhat';
import * as winston from 'winston';

type DeployResult = {
    address: string,
    abi: string,
    opHash: string
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
            filename: 'log/deploy/platform.log',
            handleExceptions: true,
            maxsize: (5 * 1024 * 1024), // 5 mb
            maxFiles: 5
        })
    ]
});

async function deployContract(contractName: string, constructorArgs: any[], deployer: SignerWithAddress): Promise<DeployResult> {
    try {
        let message = `deploying ${contractName}`;
        if (constructorArgs.length > 0) { message += ` with args: '${constructorArgs.join(',')}'`; }
        logger.info(message);

        const contractFactory = await hre.ethers.getContractFactory(contractName, deployer);
        const contractInstance = await contractFactory.connect(deployer).deploy(...constructorArgs);
        await contractInstance.deployed();

        logger.info(`deployed to ${contractInstance.address} in ${contractInstance.deployTransaction.hash}`);

        return { address: contractInstance.address, abi: contractFactory.interface.format('json') as string, opHash: contractInstance.deployTransaction.hash };
    } catch (err) {
        logger.error(`failed to deploy ${contractName}`, err);
        throw err;
    }
}

export async function deployRecordContract(contractName: string, constructorArgs: any[], deployer: SignerWithAddress, recordAs?: string) {
    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    let deploymentAddresses = JSON.parse(fs.readFileSync(deploymentLogPath).toString());

    const key = recordAs === undefined ? contractName : recordAs;
    if (deploymentAddresses[hre.network.name][key] !== undefined) {
        logger.info(`${key} already exists on ${hre.network.name} at ${deploymentAddresses[hre.network.name][key]['address']}`);
        return;
    }

    const deploymentResult = await deployContract(contractName, constructorArgs, deployer);

    deploymentAddresses[hre.network.name][key] = {
        address: deploymentResult.address,
        args: constructorArgs,
        abi: JSON.parse(deploymentResult.abi),
        verified: false
    };

    if (recordAs !== undefined) {
        deploymentAddresses[hre.network.name][key]['type'] = contractName;
    }

    fs.writeFileSync(deploymentLogPath, JSON.stringify(deploymentAddresses, undefined, 4));
}

export function getContractRecord(contractName: string) {
    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    let deploymentAddresses = JSON.parse(fs.readFileSync(deploymentLogPath).toString());

    if (deploymentAddresses[hre.network.name][contractName] === undefined) {
        throw new Error(`no deployment record for ${contractName} on ${hre.network.name}`);
    }

    const record = deploymentAddresses[hre.network.name][contractName];
    if (typeof record['abi'] === 'string') {
        record['abi'] = JSON.parse(record['abi']);
    }

    return record;
}

export function getPlatformConstant(valueName: string, defaultValue?: any): any {
    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    let deploymentAddresses = JSON.parse(fs.readFileSync(deploymentLogPath).toString());

    if (deploymentAddresses['constants'][valueName] !== undefined) {
        return deploymentAddresses['constants'][valueName];
    }

    if (defaultValue !== undefined) {
        return defaultValue;
    }

    throw new Error(`no constant value for ${valueName} on ${hre.network.name}`);
}

async function main() {
    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    if (!fs.existsSync(deploymentLogPath)) {
        fs.writeFileSync(deploymentLogPath, `{ "${hre.network.name}": { }, "constants": { } }`);
    }

    logger.info(`deploying DAOLABS Juicebox v3 fork to ${hre.network.name}`);

    const [deployer] = await hre.ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    await deployRecordContract('JBETHERC20ProjectPayerDeployer', [], deployer);
    await deployRecordContract('JBETHERC20SplitsPayerDeployer', [], deployer);
    await deployRecordContract('JBOperatorStore', [], deployer);
    await deployRecordContract('JBPrices', [deployer.address], deployer);

    const jbOperatorStoreAddress = getContractRecord('JBOperatorStore').address;
    await deployRecordContract('JBProjects', [jbOperatorStoreAddress], deployer);

    const transactionCount = await deployer.getTransactionCount();
    const expectedFundingCycleStoreAddress = hre.ethers.utils.getContractAddress({ from: deployer.address, nonce: transactionCount + 1 });
    const jbProjectsAddress = getContractRecord('JBProjects').address;
    await deployRecordContract('JBDirectory', [jbOperatorStoreAddress, jbProjectsAddress, expectedFundingCycleStoreAddress, deployer.address], deployer);

    const jbDirectoryAddress = getContractRecord('JBDirectory').address;
    await deployRecordContract('JBFundingCycleStore', [jbDirectoryAddress], deployer);

    const jbFundingCycleStoreAddress = getContractRecord('JBFundingCycleStore').address;
    await deployRecordContract('JBTokenStore', [jbOperatorStoreAddress, jbProjectsAddress, jbDirectoryAddress, jbFundingCycleStoreAddress], deployer);

    await deployRecordContract('JBSplitsStore', [jbOperatorStoreAddress, jbProjectsAddress, jbDirectoryAddress], deployer);

    const jbTokenStoreAddress = getContractRecord('JBTokenStore').address;
    const jbSplitStoreAddress = getContractRecord('JBSplitsStore').address;
    await deployRecordContract('JBController', [jbOperatorStoreAddress, jbProjectsAddress, jbDirectoryAddress, jbFundingCycleStoreAddress, jbTokenStoreAddress, jbSplitStoreAddress], deployer);

    const jbPricesAddress = getContractRecord('JBPrices').address;
    await deployRecordContract('JBSingleTokenPaymentTerminalStore', [jbDirectoryAddress, jbFundingCycleStoreAddress, jbPricesAddress], deployer);

    await deployRecordContract('JBCurrencies', [], deployer);

    const jbCurrencies_ETH = getPlatformConstant('JBCurrencies_ETH');
    const jbSingleTokenPaymentTerminalStoreAddress = getContractRecord('JBSingleTokenPaymentTerminalStore').address;
    await deployRecordContract('JBETHPaymentTerminal', [jbCurrencies_ETH, jbOperatorStoreAddress, jbProjectsAddress, jbDirectoryAddress, jbSplitStoreAddress, jbPricesAddress, jbSingleTokenPaymentTerminalStoreAddress,
        deployer.address], deployer);

    const daySeconds = 60 * 60 * 24;
    await deployRecordContract('JBReconfigurationBufferBallot', [daySeconds], deployer, 'JB1DayReconfigurationBufferBallot');
    await deployRecordContract('JBReconfigurationBufferBallot', [daySeconds * 3], deployer, 'JB3DayReconfigurationBufferBallot');
    await deployRecordContract('JBReconfigurationBufferBallot', [daySeconds * 7], deployer, 'JB7DayReconfigurationBufferBallot');

    logger.info('deployment complete');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/platform/deploy.ts --network goerli
