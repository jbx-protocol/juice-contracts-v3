import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import * as fs from 'fs';
import * as hre from 'hardhat';
import * as winston from 'winston';

import { type DeployResult } from '../lib/types';

export const logger = winston.createLogger({
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

async function deployContract(contractName: string, constructorArgs: any[], deployer: SignerWithAddress, libraries: { [key: string]: string } = {}): Promise<DeployResult> {
    try {
        let message = `deploying ${contractName}`;
        if (constructorArgs.length > 0) { message += ` with args: '${constructorArgs.join(',')}'`; }
        logger.info(message);

        const contractFactory = await hre.ethers.getContractFactory(contractName, { libraries, signer: deployer });
        const contractInstance = await contractFactory.connect(deployer).deploy(...constructorArgs);
        await contractInstance.deployed();

        logger.info(`deployed to ${contractInstance.address} in ${contractInstance.deployTransaction.hash}`);

        return { address: contractInstance.address, abi: contractFactory.interface.format('json') as string, opHash: contractInstance.deployTransaction.hash };
    } catch (err) {
        logger.error(`failed to deploy ${contractName}`, err);
        throw err;
    }
}

export async function deployRecordContract(contractName: string, constructorArgs: any[], deployer: SignerWithAddress, recordAs?: string, logPath = `./deployments/${hre.network.name}/platform.json`, libraries: { [key: string]: string } = {}) {
    let deploymentAddresses = JSON.parse(fs.readFileSync(logPath).toString());

    const key = recordAs === undefined ? contractName : recordAs;
    if (deploymentAddresses[hre.network.name][key] !== undefined) {
        logger.info(`${key} already exists on ${hre.network.name} at ${deploymentAddresses[hre.network.name][key]['address']}`);
        return;
    }

    const deploymentResult = await deployContract(contractName, constructorArgs, deployer, libraries);

    deploymentAddresses[hre.network.name][key] = {
        address: deploymentResult.address,
        args: constructorArgs,
        abi: JSON.parse(deploymentResult.abi),
        verified: false
    };

    if (recordAs !== undefined) {
        deploymentAddresses[hre.network.name][key]['type'] = contractName;
    }

    fs.writeFileSync(logPath, JSON.stringify(deploymentAddresses, undefined, 4));
}

export async function recordContractAbi(contractName: string, deployer: SignerWithAddress, recordAs?: string, logPath = `./deployments/${hre.network.name}/platform.json`, libraries: { [key: string]: string } = {}) {
    let deploymentAddresses = JSON.parse(fs.readFileSync(logPath).toString());

    const key = recordAs === undefined ? contractName : recordAs;
    if (deploymentAddresses[hre.network.name][key] !== undefined) {
        logger.info(`${key} already exists on ${hre.network.name} at ${deploymentAddresses[hre.network.name][key]['address']}`);
        return;
    }

    let abi: string;
    try {
        let message = `generating abi for ${contractName}`;
        logger.info(message);

        const contractFactory = await hre.ethers.getContractFactory(contractName, { libraries, signer: deployer });

        abi = contractFactory.interface.format('json') as string;
    } catch (err) {
        logger.error(`failed to generate abi ${contractName}`, err);
        throw err;
    }

    deploymentAddresses[hre.network.name][key] = {
        address: '',
        args: [],
        abi: JSON.parse(abi),
        verified: false
    };

    if (recordAs !== undefined) {
        deploymentAddresses[hre.network.name][key]['type'] = contractName;
    }

    fs.writeFileSync(logPath, JSON.stringify(deploymentAddresses, undefined, 4));
}

export function getContractRecord(contractName: string, logPath = `./deployments/${hre.network.name}/platform.json`, network = hre.network.name) {
    let deploymentAddresses = JSON.parse(fs.readFileSync(logPath).toString());

    if (deploymentAddresses[network][contractName] === undefined) {
        throw new Error(`no deployment record for ${contractName} on ${network}`);
    }

    const record = deploymentAddresses[network][contractName];
    if (typeof record['abi'] === 'string') {
        record['abi'] = JSON.parse(record['abi']);
    }

    return record;
}

export function getPlatformConstant(valueName: string, defaultValue?: any, logPath = `./deployments/${hre.network.name}/platform.json`): any {
    let deploymentAddresses = JSON.parse(fs.readFileSync(logPath).toString());

    if (deploymentAddresses['constants'][valueName] !== undefined) {
        return deploymentAddresses['constants'][valueName];
    }

    if (defaultValue !== undefined) {
        return defaultValue;
    }

    throw new Error(`no constant value for ${valueName} on ${hre.network.name}`);
}

export async function verifyContract(contractName: string, contractAddress: string, constructorArgs: any[]): Promise<boolean> {
    try {
        logger.info(`verifying ${contractName} on ${hre.network.name} at ${contractAddress} with Etherscan`);
        await hre.run('verify:verify', { address: contractAddress, constructorArguments: constructorArgs });
        logger.info('verification complete');

        return true;
    } catch (err) {
        logger.error(`failed to verify ${contractName} with Etherscan`, err);

        return false;
    }
}

export async function verifyRecordContract(contractName: string, contractAddress: string, constructorArgs: any[], logPath = `./deployments/${hre.network.name}/platform.json`) {
    let deploymentAddresses = JSON.parse(fs.readFileSync(logPath).toString());

    const result = await verifyContract(contractName, contractAddress, constructorArgs);
    deploymentAddresses[hre.network.name][contractName]['verified'] = result;

    fs.writeFileSync(logPath, JSON.stringify(deploymentAddresses, undefined, 4));
}
