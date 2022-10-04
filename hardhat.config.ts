import * as dotenv from 'dotenv';
import { task } from 'hardhat/config';
import * as taskNames from 'hardhat/builtin-tasks/task-names';
import fs from 'fs';

import '@ethereum-waffle/chai';
import '@nomicfoundation/hardhat-chai-matchers';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-waffle';
import '@openzeppelin/hardhat-upgrades';
import '@typechain/hardhat';
import 'hardhat-contract-sizer';
import 'hardhat-deploy';
import 'hardhat-gas-reporter';
import 'solidity-coverage';
import 'solidity-docgen';

dotenv.config();

const INFURA_API_KEY = process.env.INFURA_API_KEY;
const ALCHEMY_MAINNET_URL = process.env.ALCHEMY_MAINNET_URL;
const ALCHEMY_MAINNET_KEY = process.env.ALCHEMY_MAINNET_API_KEY;
const REPORT_GAS = process.env.REPORT_GAS;
const COINMARKETCAP_KEY = process.env.COINMARKETCAP_API_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

const defaultNetwork = 'hardhat';

function mnemonic() {
    try {
        return fs.readFileSync('./mnemonic.txt').toString().trim();
    } catch (e) {
        if (defaultNetwork !== 'localhost') {
            console.log('☢️ WARNING: No mnemonic file created for a deploy account.');
        }
    }
    return '';
}

const infuraId = process.env.INFURA_ID || INFURA_API_KEY;

module.exports = {
    defaultNetwork,
    networks: {
        hardhat: {
            forking: {
                url: `${ALCHEMY_MAINNET_URL}/${ALCHEMY_MAINNET_KEY}`,
                blockNumber: 15416229,
                enabled: false
            },
            allowUnlimitedContractSize: true,
            blockGasLimit: 100_000_000
        },
        localhost: {
            url: 'http://localhost:8545',
            blockGasLimit: 0x1fffffffffffff,
        },
        goerli: {
            url: 'https://goerli.infura.io/v3/' + infuraId,
            accounts: {
                mnemonic: mnemonic(),
            },
        },
        mainnet: {
            url: 'https://mainnet.infura.io/v3/' + infuraId,
            accounts: {
                mnemonic: mnemonic(),
            },
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
        feeCollector: {
            default: 0,
        },
    },
    solidity: {
        version: '0.8.16',
        settings: {
            optimizer: {
                enabled: true,
                // https://docs.soliditylang.org/en/v0.8.10/internals/optimizer.html#:~:text=Optimizer%20Parameter%20Runs,-The%20number%20of&text=A%20%E2%80%9Cruns%E2%80%9D%20parameter%20of%20%E2%80%9C,is%202**32%2D1%20.
                runs: 10000,
            },
        },
    },
    contractSizer: {
        alphaSort: true,
        disambiguatePaths: false,
        runOnCompile: true,
        strict: false
    },
    gasReporter: {
        enabled: REPORT_GAS !== undefined,
        currency: 'USD',
        gasPrice: 30,
        showTimeSpent: true,
        coinmarketcap: COINMARKETCAP_KEY
    },
    etherscan: {
        apiKey: ETHERSCAN_API_KEY
    },
    mocha: {
        timeout: 30 * 60 * 1000,
        bail: false
    },
    docgen: {}
};

// List details of deployer account.
task('account', 'Get balance information for the deployment account.', async (_, { ethers }) => {
    const hdkey = require('ethereumjs-wallet/hdkey');
    const bip39 = require('bip39');
    let mnemonic = fs.readFileSync('./mnemonic.txt').toString().trim();
    const seed = await bip39.mnemonicToSeed(mnemonic);
    const hdwallet = hdkey.fromMasterSeed(seed);
    const wallet_hdpath = "m/44'/60'/0'/0/";
    const account_index = 0;
    let fullPath = wallet_hdpath + account_index;
    const wallet = hdwallet.derivePath(fullPath).getWallet();
    var EthUtil = require('ethereumjs-util');
    const address = '0x' + EthUtil.privateToAddress(wallet._privKey).toString('hex');

    console.log('Deployer Account: ' + address);
    for (let n in config.networks) {
        try {
            let provider = new ethers.providers.JsonRpcProvider(config.networks[n].url);
            let balance = await provider.getBalance(address);
            console.log(' -- ' + n + ' --  -- -- 📡 ');
            console.log('   balance: ' + ethers.utils.formatEther(balance));
            console.log('   nonce: ' + (await provider.getTransactionCount(address)));
        } catch (e) {
            console.log(e);
        }
    }
});

task('compile:one', 'Compiles a single contract in isolation')
    .addPositionalParam('contractName')
    .setAction(async function (args, env) {
        const sourceName = env.artifacts.readArtifactSync(args.contractName).sourceName;

        const dependencyGraph = await env.run(taskNames.TASK_COMPILE_SOLIDITY_GET_DEPENDENCY_GRAPH, {
            sourceNames: [sourceName],
        });

        const resolvedFiles = dependencyGraph.getResolvedFiles().filter((resolvedFile) => {
            return resolvedFile.sourceName === sourceName;
        });

        const compilationJob = await env.run(
            taskNames.TASK_COMPILE_SOLIDITY_GET_COMPILATION_JOB_FOR_FILE,
            {
                dependencyGraph,
                file: resolvedFiles[0],
            },
        );

        await env.run(taskNames.TASK_COMPILE_SOLIDITY_COMPILE_JOB, {
            compilationJob,
            compilationJobs: [compilationJob],
            compilationJobIndex: 0,
            emitsArtifacts: true,
            quiet: true,
        });
    });

task('deploy-ballot', 'Deploy a buffer ballot of a given duration')
    .addParam('duration', 'Set the ballot duration (in seconds)')
    .setAction(async (taskArgs, hre) => {
        try {
            const { get, deploy } = deployments;
            const [deployer] = await hre.ethers.getSigners();

            // Take the previously deployed
            const JBFundingCycleStoreDeployed = await get('JBFundingCycleStore');

            const JB3DayReconfigurationBufferBallot = await deploy('JBReconfigurationBufferBallot', {
                from: deployer.address,
                log: true,
                args: [taskArgs.duration, JBFundingCycleStoreDeployed.address],
            });

            console.log('Buffer ballot deployed at ' + JB3DayReconfigurationBufferBallot.address);
        } catch (error) {
            console.log(error);
        }
    });
