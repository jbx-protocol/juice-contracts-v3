const { ethers } = require('hardhat');

/**
 * Deploys the Juicebox V3.1.1 contract ecosystem.
 *
 * Example usage:
 *
 * npx hardhat deploy --network goerli --tags 311
 */
module.exports = async ({ deployments, getChainId }) => {
  console.log('Deploying v3.1.1 contracts...');

  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  let ownerAddress;
  let chainlinkV2UsdEthPriceFeed;
  let chainId = await getChainId();
  let baseDeployArgs = {
    from: deployer.address,
    log: true,
    skipIfAlreadyDeployed: true,
  };

  switch (chainId) {
    // mainnet
    case '1':
      ownerAddress = '0xAF28bcB48C40dBC86f52D459A6562F658fc94B1e';
      chainlinkV2UsdEthPriceFeed = '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419';
      break;
    // Goerli
    case '5':
      ownerAddress = '0x46D623731E179FAF971CdA04fF8c499C95461b3c';
      chainlinkV2UsdEthPriceFeed = '0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e';
      break;
    // Sepolia
    case '11155111':
      ownerAddress = '0xAF28bcB48C40dBC86f52D459A6562F658fc94B1e';
      chainlinkV2UsdEthPriceFeed = '0x694AA1769357215DE4FAC081bf1f309aDC325306';
      break;
    // hardhat / localhost
    case '31337':
      ownerAddress = deployer.address;

      protocolProjectStartsAtOrAfter = 0;
      break;
  }

  console.log({ ownerAddress });

  // Deploy a JBOperatorStore contract.
  const JBOperatorStore = await deploy('JBOperatorStore', {
    ...baseDeployArgs,
    args: [],
  });

  // Deploy a JBPrices contract.
  const JBPrices = await deploy('JBPrices', {
    ...baseDeployArgs,
    args: [deployer.address],
  });

  // Deploy a JBProjects contract.
  const JBProjects = await deploy('JBProjects', {
    ...baseDeployArgs,
    args: [JBOperatorStore.address],
  });

  // Get the future address of JBFundingCycleStore
  const transactionCount = await deployer.getTransactionCount();

  const FundingCycleStoreFutureAddress = ethers.utils.getContractAddress({
    from: deployer.address,
    nonce: transactionCount + 1,
  });

  // Deploy a JBDirectory.
  const JBDirectory = await deploy('JBDirectory', {
    ...baseDeployArgs,
    args: [
      JBOperatorStore.address,
      JBProjects.address,
      FundingCycleStoreFutureAddress,
      deployer.address,
    ],
  });

  // Deploy a JBFundingCycleStore.
  const JBFundingCycleStore = await deploy('JBFundingCycleStore', {
    ...baseDeployArgs,
    contract: 'contracts/JBFundingCycleStore.sol:JBFundingCycleStore',
    args: [JBDirectory.address],
  });

  // Deploy a JBTokenStore.
  const JBTokenStore = await deploy('JBTokenStore', {
    ...baseDeployArgs,
    args: [
      JBOperatorStore.address,
      JBProjects.address,
      JBDirectory.address,
      JBFundingCycleStore.address,
    ],
  });

  // Deploy a JBSplitStore.
  const JBSplitStore = await deploy('JBSplitsStore', {
    ...baseDeployArgs,
    contract: 'contracts/JBSplitsStore.sol:JBSplitsStore',
    args: [JBOperatorStore.address, JBProjects.address, JBDirectory.address],
  });

  // Deploy a fund access constraints store
  const JBFundAccessConstraintsStore = await deploy('JBFundAccessConstraintsStore', {
    ...baseDeployArgs,
    contract: 'contracts/JBFundAccessConstraintsStore.sol:JBFundAccessConstraintsStore',
    args: [JBDirectory.address],
  });

  // Deploy a JBController contract.
  const JBController = await deploy('JBController3_1', {
    ...baseDeployArgs,
    contract: 'contracts/JBController3_1.sol:JBController3_1',
    args: [
      JBOperatorStore.address,
      JBProjects.address,
      JBDirectory.address,
      JBFundingCycleStore.address,
      JBTokenStore.address,
      JBSplitStore.address,
      JBFundAccessConstraintsStore.address,
    ],
  });

  // Deploy a JBSingleTokenPaymentTerminalStore contract.
  const JBSingleTokenPaymentTerminalStore = await deploy('JBSingleTokenPaymentTerminalStore3_1_1', {
    ...baseDeployArgs,
    contract:
      'contracts/JBSingleTokenPaymentTerminalStore3_1_1.sol:JBSingleTokenPaymentTerminalStore3_1_1',
    args: [JBDirectory.address, JBFundingCycleStore.address, JBPrices.address],
  });

  // Deploy the currencies library.
  const JBCurrencies = await deploy('JBCurrencies', {
    ...baseDeployArgs,
    args: [],
  });

  // Get references to contract that will have transactions triggered.
  const jbDirectoryContract = new ethers.Contract(JBDirectory.address, JBDirectory.abi);
  const jbPricesContract = new ethers.Contract(JBPrices.address, JBPrices.abi);
  const jbControllerContract = new ethers.Contract(JBController.address, JBController.abi);
  const jbProjectsContract = new ethers.Contract(JBProjects.address, JBProjects.abi);
  const jbCurrenciesLibrary = new ethers.Contract(JBCurrencies.address, JBCurrencies.abi);

  // Get a reference to USD and ETH currency indexes.
  const USD = await jbCurrenciesLibrary.connect(deployer).USD();
  const ETH = await jbCurrenciesLibrary.connect(deployer).ETH();

  // Deploy a JBETHPaymentTerminal contract.
  await deploy('JBETHPaymentTerminal3_1_1', {
    ...baseDeployArgs,
    contract: 'contracts/JBETHPaymentTerminal3_1_1.sol:JBETHPaymentTerminal3_1_1',
    args: [
      ETH,
      JBOperatorStore.address,
      JBProjects.address,
      JBDirectory.address,
      JBSplitStore.address,
      JBPrices.address,
      JBSingleTokenPaymentTerminalStore.address,
      ownerAddress,
    ],
  });

  // Deploy a JBETHERC20ProjectPayerDeployer contract.
  await deploy('JBETHERC20ProjectPayerDeployer', {
    ...baseDeployArgs,
    args: [JBDirectory.address],
  });

  // Deploy a JBETHERC20SplitsPayerDeployer contract.
  await deploy('JBETHERC20SplitsPayerDeployer', {
    ...baseDeployArgs,
    contract: 'contracts/JBETHERC20SplitsPayerDeployer.sol:JBETHERC20SplitsPayerDeployer',
    args: [JBSplitStore.address],
  });

  // Get a reference to an existing ETH/USD feed.
  const usdEthFeed = await jbPricesContract.connect(deployer).feedFor(USD, ETH);

  // If needed, deploy an ETH/USD price feed and add it to the store.
  if (chainlinkV2UsdEthPriceFeed && usdEthFeed == ethers.constants.AddressZero) {
    // Deploy a JBChainlinkV3PriceFeed contract for ETH/USD.
    const JBChainlinkV3UsdEthPriceFeed = await deploy('JBChainlinkV3PriceFeed', {
      ...baseDeployArgs,
      args: [chainlinkV2UsdEthPriceFeed],
    });

    //The base currency is ETH since the feed returns the USD price of 1 ETH.
    await jbPricesContract
      .connect(deployer)
      .addFeedFor(USD, ETH, JBChainlinkV3UsdEthPriceFeed.address);
  }

  // If needed, transfer the ownership of the JBPrices to to the multisig.
  if ((await jbPricesContract.connect(deployer).owner()) != ownerAddress) {
    let tx = await jbPricesContract.connect(deployer).transferOwnership(ownerAddress);
    await tx.wait();
  }

  // If needed, transfer the ownership of the JBProjects to to the multisig.
  if ((await jbProjectsContract.connect(deployer).owner()) != ownerAddress) {
    let tx = await jbProjectsContract.connect(deployer).transferOwnership(ownerAddress);
    await tx.wait();
  }

  let isAllowedToSetFirstController = await jbDirectoryContract
    .connect(deployer)
    .isAllowedToSetFirstController(JBController.address);

  // If needed, allow the controller to set projects' first controller, then transfer the ownership of the JBDirectory to the multisig.
  if (!isAllowedToSetFirstController) {
    let tx = await jbDirectoryContract
      .connect(deployer)
      .setIsAllowedToSetFirstController(JBController.address, true);
    await tx.wait();
  }

  // If needed, transfer the ownership of the JBDirectory contract to the multisig.
  if ((await jbDirectoryContract.connect(deployer).owner()) != ownerAddress) {
    let tx = await jbDirectoryContract.connect(deployer).transferOwnership(ownerAddress);
    await tx.wait();
  }

  //
  // If you want, deploy funding cycle ballot contracts for projects to use.
  //

  // // Deploy a JB1DayReconfigurationBufferBallot.
  // await deploy('JB1DayReconfigurationBufferBallot', {
  //   ...baseDeployArgs,
  //   contract: 'contracts/JBReconfigurationBufferBallot.sol:JBReconfigurationBufferBallot',
  //   args: [86400],
  // });

  // // Deploy a JB3DayReconfigurationBufferBallot.
  // await deploy('JB3DayReconfigurationBufferBallot', {
  //   ...baseDeployArgs,
  //   contract: 'contracts/JBReconfigurationBufferBallot.sol:JBReconfigurationBufferBallot',
  //   args: [259200],
  // });

  // // Deploy a JB7DayReconfigurationBufferBallot.
  // await deploy('JB7DayReconfigurationBufferBallot', {
  //   ...baseDeployArgs,
  //   contract: 'contracts/JBReconfigurationBufferBallot.sol:JBReconfigurationBufferBallot',
  //   args: [604800],
  // });

  console.log('Done');
};

module.exports.tags = ['311'];
