import * as fs from 'fs';
import * as hre from 'hardhat';
import * as winston from 'winston';

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

async function verifyContract(contractName: string, contractAddress: string, constructorArgs: any[]): Promise<boolean> {
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

async function verifyRecordContract(contractName: string, contractAddress: string, constructorArgs: any[]) {
    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    let deploymentAddresses = JSON.parse(fs.readFileSync(deploymentLogPath).toString());

    const result = await verifyContract(contractName, contractAddress, constructorArgs);
    deploymentAddresses[hre.network.name][contractName]['verified'] = result;

    fs.writeFileSync(deploymentLogPath, JSON.stringify(deploymentAddresses, undefined, 4));
}

async function main() {
    const deploymentLogPath = `./deployments/${hre.network.name}/platform.json`;
    let deployedContracts = JSON.parse(fs.readFileSync(deploymentLogPath).toString());

    const contractKeys = Object.keys(deployedContracts[hre.network.name]);
    const unverifiedContracts = contractKeys.filter(k => !deployedContracts[hre.network.name][k]['verified']);

    for (const unverified of unverifiedContracts) {
        await verifyRecordContract(unverified, deployedContracts[hre.network.name][unverified]['address'], deployedContracts[hre.network.name][unverified]['args']);
    }

    logger.info('verification complete');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/platform/verify.ts --network goerli