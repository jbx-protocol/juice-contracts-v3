import * as dotenv from "dotenv";
import { ethers } from 'hardhat';
import * as hre from 'hardhat';
import * as winston from 'winston';

import { deployRecordContract, getContractRecord, verifyRecordContract } from '../lib/lib';

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
                filename: 'log/deploy/NFToken.log',
                handleExceptions: true,
                maxsize: (5 * 1024 * 1024), // 5 mb
                maxFiles: 5
            })
        ]
    });

    ///
    logger.info(`deploying sample NFToken to ${hre.network.name}`);

    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;

    const [deployer] = await ethers.getSigners();
    logger.info(`connected as ${deployer.address}`);

    const tokenName = 'aaa token';
    const tokenSymbol = 'aaa';
    const baseUri = '';
    const contractUri = '';
    const projectId = 0;
    const jbxDirectoryAddress = ethers.constants.AddressZero;
    const maxSupply = 1;
    const unitPrice = ethers.utils.parseEther('100.001');
    const MintAllowance = 1;
    const mintPeriodStart = 0
    const mintPeriodEnd = 0;

    const params = [tokenName,
        tokenSymbol,
        baseUri,
        contractUri,
        projectId,
        jbxDirectoryAddress,
        maxSupply,
        unitPrice,
        MintAllowance,
        mintPeriodStart,
        mintPeriodEnd];
    await deployRecordContract('NFToken', params, deployer, 'NFToken', `./deployments/${hre.network.name}/extensions.json`);
    const nfTokenRecord = getContractRecord('NFToken', deploymentLogPath);
    // await verifyRecordContract('NFToken', nfTokenRecord.address, nfTokenRecord.args, deploymentLogPath);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/NFToken.ts --network goerli
