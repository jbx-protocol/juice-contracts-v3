const { ethers } = require('hardhat');
const directoryGoerli = require('../deployments/goerli/JBDirectory.json');
const directoryMainnet = require('../deployments/mainnet/JBDirectory.json');
const splitsStoreGoerli = require('../deployments/goerli/JBSplitsStore.json');
const splitsStoreMainnet = require('../deployments/mainnet/JBSplitsStore.json');

/**
 * Deploys the project and splits payer deployer contracts.
 *
 * Example usage:
 *
 * npx hardhat deploy --network goerli --tags project_payer
 */
module.exports = async ({ deployments, getChainId }) => {
  console.log('Deploying projects and splits payer');

  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  let multisigAddress;
  let jbDirectory;
  let jbSplitsStore;
  let chainId = await getChainId();
  let baseDeployArgs = {
    from: deployer.address,
    log: true,
    skipIfAlreadyDeployed: true,
  };

  console.log({ deployer: deployer.address, chain: chainId });

  switch (chainId) {
    // mainnet
    case '1':
      multisigAddress = '0xAF28bcB48C40dBC86f52D459A6562F658fc94B1e';
      jbDirectory = directoryMainnet.address;
      jbSplitsStore = splitsStoreMainnet.address;
      break;
    // Goerli
    case '5':
      multisigAddress = '0x46D623731E179FAF971CdA04fF8c499C95461b3c';
      jbDirectory = directoryGoerli.address;
      jbSplitsStore = splitsStoreGoerli.address;
      break;
  }

  console.log({ multisigAddress, jbDirectory });

  // Deploy a JBETHERC20ProjectPayerDeployer contract.
  let jbProjectPayer = await deploy('JBETHERC20ProjectPayerDeployer', {
    ...baseDeployArgs,
    args: [jbDirectory],
  });

  // Deploy a JBETHERC20SplitsPayerDeployer contract.
  let jbSplitsPayer = await deploy('JBETHERC20SplitsPayerDeployer', {
    ...baseDeployArgs,
    contract: 'contracts/JBETHERC20SplitsPayerDeployer.sol:JBETHERC20SplitsPayerDeployer',
    args: [jbSplitsStore],
  });

  console.log('JBETHERC20ProjectPayerDeployer address: ' + jbProjectPayer.address);
  console.log('JBETHERC20SplitsPayerDeployer address: ' + jbSplitsPayer.address);

  console.log('Done');
};

module.exports.tags = ['project_payer'];
