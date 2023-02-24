import * as dotenv from 'dotenv';
import { task } from 'hardhat/config';
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
const PRIVATE_KEY = process.env.PRIVATE_KEY;

type ProviderNetwork = 'localhost' | 'hardhat';

const defaultNetwork: ProviderNetwork = 'hardhat';

function accountSeed() {
  if (PRIVATE_KEY !== undefined) {
    return [PRIVATE_KEY];
  } else if (fs.existsSync('./mnemonic.txt')) {
    return { mnemonic: fs.readFileSync('./mnemonic.txt').toString().trim() };
  } else if (defaultNetwork !== 'localhost') {
    console.log('☢️ WARNING: No mnemonic file created for a deploy account.');
  }

  return { mnemonic: '' };
}

const infuraId = process.env.INFURA_ID || INFURA_API_KEY;

module.exports = {
  defaultNetwork,
  networks: {
    hardhat: {
      // forking: {
      //     url: `${ALCHEMY_MAINNET_URL}/${ALCHEMY_MAINNET_KEY}`,
      //     blockNumber: 15416229,
      //     enabled: false
      // },
      forking: {
        // url: 'https://goerli.infura.io/v3/' + infuraId,
        // blockNumber: 8472216,
        url: 'https://mainnet.infura.io/v3/' + infuraId,
        blockNumber: 16399768,
        enabled: true
      },
      allowUnlimitedContractSize: true,
      blockGasLimit: 100_000_000
    },
    paths: {
        sources: './contracts/',
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
    goerli: {
      url: 'https://goerli.infura.io/v3/' + infuraId,
      accounts: accountSeed()
    },
    mainnet: {
      url: 'https://mainnet.infura.io/v3/' + infuraId,
      accounts: accountSeed()
    }
  },
  namedAccounts: {
    deployer: {
      default: 0
    },
    feeCollector: {
      default: 0
    }
  },
  solidity: {
    version: '0.8.14',
    settings: {
      optimizer: {
        enabled: true,
        // https://docs.soliditylang.org/en/v0.8.10/internals/optimizer.html#:~:text=Optimizer%20Parameter%20Runs,-The%20number%20of&text=A%20%E2%80%9Cruns%E2%80%9D%20parameter%20of%20%E2%80%9C,is%202**32%2D1%20.
        runs: 10000
      }
    }
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

task('deploy-ballot', 'Deploy a buffer ballot of a given duration')
  .addParam('duration', 'Set the ballot duration (in seconds)')
  .setAction(async (taskArgs, hre) => {
    try {
      const { deploy } = hre.deployments;
      const [deployer] = await hre.ethers.getSigners();

      const JBReconfigurationBufferBallot = await deploy('JBReconfigurationBufferBallot', {
        from: deployer.address,
        log: true,
        args: [taskArgs.duration]
      });

      console.log('Buffer ballot deployed at ' + JBReconfigurationBufferBallot.address);
    } catch (error) {
      console.log(error);
    }
  });
