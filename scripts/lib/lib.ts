import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import fetch from 'node-fetch';
import * as fs from 'fs';
import * as hre from 'hardhat';
import * as path from 'path';
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

function sleep(ms = 1_000) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

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

async function getCachedAbi(contractAddress: string, cachePath: string = `./abicache/${hre.network.name}`): Promise<any | undefined> {
    try {
        if (!fs.existsSync(cachePath)) {
            fs.mkdirSync(cachePath, { recursive: true });
        }
        const abi = await fs.promises.readFile(`${cachePath}/${contractAddress}.json`, 'utf-8');
        return JSON.parse(abi);
    } catch (error: any) {
        return undefined;
    }
}

/**
 * Download and store JSON abi for a given contract address on "current" network.
 * 
 * @param contractAddress Contract address to get abi for.
 * @param etherscanKey Optional Etherscan key.
 * @param isProxy If true, will attempt to parse target contract as an EIP1967 proxy to get implementation address.
 * @returns abi JSON.
 */
export async function abiFromAddress(contractAddress: string, etherscanKey: string, isProxy: boolean = false): Promise<any> {
    if (isProxy) {
        const eip1967 = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc';
        const implementationAddress = (await hre.ethers.getDefaultProvider().getStorageAt(contractAddress, eip1967)).slice(-40);
        return abiFromAddress(`0x${implementationAddress}`, etherscanKey, false);
    } else {
        const abi = await getCachedAbi(contractAddress);
        if (abi) {
            return abi;
        }

        logger.info(`getting abi for ${contractAddress} on ${hre.network.name}`);
        console.log(``);
        const data = await fetch(`https://api.etherscan.io/api?module=contract&action=getabi&address=${contractAddress}&apikey=${etherscanKey}`)
            .then((response: any) => response.json())
            .then((data: any) => data['result']);
        await sleep(1_500); // throttle etherscan
        await fs.promises.writeFile(`./abicache/${hre.network.name}/${contractAddress}.json`, data, 'utf-8');
        return JSON.parse(data);
    }
}

export function exportContractInterfaces(logPath = `./deployments/${hre.network.name}/platform.json`, outputPath = `./exports/daolabs`) {
    const combinedLog = JSON.parse(fs.readFileSync(logPath).toString());

    const network = Object.keys(combinedLog)[0];
    const contractList = Object.keys(combinedLog[network]);

    for (const c of contractList) {
        const contractFilePath = path.join(outputPath, `${c}.json`);
        let fileContent = {};

        if (fs.existsSync(contractFilePath)) {
            fileContent = JSON.parse(fs.readFileSync(contractFilePath).toString());
        }

        fileContent[network] = combinedLog[network][c]['address'];
        fileContent['abi'] = combinedLog[network][c]['abi'];

        fs.writeFileSync(contractFilePath, JSON.stringify(fileContent, undefined, 4));
    }
}
