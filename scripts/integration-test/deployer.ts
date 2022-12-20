import * as dotenv from "dotenv";
import { ethers } from 'hardhat';
import * as hre from 'hardhat';
import { BigNumber, type ContractTransaction } from 'ethers';
import * as winston from 'winston';
import { Provider } from "@ethersproject/abstract-provider";
import { Signer } from "@ethersproject/abstract-signer";
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

import { getContractRecord } from '../lib/lib';

let logger;

const platform = `./deployments/${hre.network.name}/platform.json`; // NOTE: this path is relative to the execution directory
const extensions = `./deployments/${hre.network.name}/extensions.json`; // NOTE: this path is relative to the execution directory

export async function deployNFToken(
    owner: string,
    tokenName: string,
    tokenSymbol: string,
    baseUri: string,
    contractUri: string,
    jbxProjectId: number,
    jbxDirectory: string,
    maxSupply: number,
    unitPrice: number | BigNumber,
    mintAllowance: number,
    mintPeriodStart: number,
    mintPeriodEnd: number,
    opts: any = {},
    actualProvider: Signer | Provider,
): Promise<ContractTransaction> {
    const deployerProxyRecord = getContractRecord('DeployerProxy', extensions, hre.network.name);

    const contract = new ethers.Contract(
        deployerProxyRecord.address,
        deployerProxyRecord.abi,
        actualProvider,
    );

    return contract.functions.deployNFToken(
        owner,
        tokenName,
        tokenSymbol,
        baseUri,
        contractUri,
        jbxProjectId,
        jbxDirectory,
        maxSupply,
        unitPrice,
        mintAllowance,
        mintPeriodStart,
        mintPeriodEnd,
        opts,
    ) as Promise<ContractTransaction>;
}

async function main() {
    dotenv.config();

    logger = winston.createLogger({
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
                filename: 'log/integration/deployer.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    const deployerProxyRecord = getContractRecord('DeployerProxy', extensions, hre.network.name);
    logger.info(`running deployer integration tests on ${hre.network.name} for ${deployerProxyRecord.address}`);

    const [deployer]: SignerWithAddress[] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    try {
        let tx = await deployNFToken(
            deployer.address, // owner
            'Sample DAOLABS NFToken', // tokenName
            'SDN', // tokenSymbol
            'ipfs://', // baseUri
            'ipfs://', // contractUri
            0, // jbxProjectId
            ethers.constants.AddressZero, // jbxDirectory or platform.JBDirectory.address
            100, // maxSupply
            ethers.utils.parseEther('0.001'), // unitPrice
            10, // mintAllowance
            0, // mintPeriodStart
            0, // mintPeriodEnd
            {}, // opts
            deployer
        );
        logger.info(`calling deployNFToken in ${tx.hash}`);
        let receipt = await tx.wait();
        let [contractType, contractAddress] = receipt.events.filter((e) => e.event === 'Deployment')[0].args;
        logger.info(`deployed ${contractType} at ${contractAddress}`);
    } catch (err) {
        logger.error(`failed on deployNFToken with ${err.message}`);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/integration-test/deployer.ts --network goerli
