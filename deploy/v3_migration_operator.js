const { ethers } = require('hardhat');

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
      jbDirectory = '0x65572FB928b46f9aDB7cfe5A4c41226F636161ea';
      break;
    // Goerli
    case '5':
      multisigAddress = '0x46D623731E179FAF971CdA04fF8c499C95461b3c';
      jbDirectory = '0x8E05bcD2812E1449f0EC3aE24E2C395F533d9A99';
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
