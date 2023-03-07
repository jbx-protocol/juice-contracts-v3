const { ethers } = require('hardhat');
const directoryGoerli = require('../deployments/goerli/JBDirectory.json')
const directoryMainnet = require('../deployments/mainnet/JBDirectory.json')

/**
 * Deploys the Migration Operator contract to migrate the controller & terminal.
 *
 * Example usage:
 *
 * npx hardhat deploy --network goerli --tags JB_Migration_Operator
 */
module.exports = async ({ deployments, getChainId }) => {
  console.log('Deploying v3 Migration Operator');

  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  let multisigAddress;
  let jbDirectory;
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
      break;
    // Goerli
    case '5':
      multisigAddress = '0x46D623731E179FAF971CdA04fF8c499C95461b3c';
      jbDirectory = directoryGoerli.address;
      break;
  }

  console.log({ multisigAddress, jbDirectory });

  // // Deploy the JBMigrationOperator contract.
  const JBMigrationOperator = await deploy('JBMigrationOperator', {
      ...baseDeployArgs,
      args: [
        jbDirectory,
      ],
  });

  console.log('Done');
};

module.exports.tags = ['JB_Migration_Operator'];
