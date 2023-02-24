import * as fs from 'fs';
import * as hre from 'hardhat';

import { logger, verifyRecordContract } from '../lib/lib';

async function main() {
    const deploymentLogPath = `./deployments/${hre.network.name}/extensions.json`;
    let deployedContracts = JSON.parse(fs.readFileSync(deploymentLogPath).toString());

    const contractKeys = Object.keys(deployedContracts[hre.network.name]);
    const unverifiedContracts = contractKeys.filter(k => !deployedContracts[hre.network.name][k]['verified']);

    for (const unverified of unverifiedContracts) {
        await verifyRecordContract(unverified, deployedContracts[hre.network.name][unverified]['address'], deployedContracts[hre.network.name][unverified]['args'], deploymentLogPath);
    }

    logger.info('verification complete');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/deploy/verify.ts --network goerli
