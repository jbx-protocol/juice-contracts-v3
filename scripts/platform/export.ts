import * as fs from 'fs';
import * as hre from 'hardhat';
import * as path from 'path';


import { logger, exportContractInterfaces } from '../lib/lib';

async function main() {
    const outputPath = './exports/daolabs';

    if (!fs.existsSync(outputPath)) {
        throw new Error(`output path, '${outputPath}', does not exist`);
    }

    logger.info(`exporting contract interfaces to ${outputPath}`);

    exportContractInterfaces(path.join('deployments', hre.network.name, 'platform.json'), outputPath);
    exportContractInterfaces(path.join('deployments', hre.network.name, 'extensions.json'), outputPath);

    logger.info('interface export complete');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

// npx hardhat run scripts/platform/export.ts --network goerli
