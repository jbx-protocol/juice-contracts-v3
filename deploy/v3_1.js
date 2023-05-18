const { ethers } = require('hardhat');

/**
 * Deploys the Juicebox V2 contract ecosystem.
 *
 * Example usage:
 *
 * npx hardhat deploy --network goerli --tags 31
 */
module.exports = async ({ deployments, getChainId }) => {
  console.log('Deploying v3.1 contracts...');

  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  let governanceAddress;
  let chainlinkV2UsdGasCurrencyPriceFeed;
  let chainId = await getChainId();
  let baseDeployArgs = {
    from: deployer.address,
    log: true,
    skipIfAlreadyDeployed: true,
  };
  let protocolProjectStartsAtOrAfter;

  console.log({ deployer: deployer.address, chain: chainId });

  switch (chainId) {
    // mainnet
    case '1':
      governanceAddress = '0xAF28bcB48C40dBC86f52D459A6562F658fc94B1e';
      chainlinkV2UsdGasCurrencyPriceFeed = '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419';
      protocolProjectStartsAtOrAfter = 1664047173;
      break;
    // Goerli
    case '5':
      governanceAddress = '0x46D623731E179FAF971CdA04fF8c499C95461b3c';
      chainlinkV2UsdGasCurrencyPriceFeed = '0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e';
      protocolProjectStartsAtOrAfter = 0;
      break;
    // Polygon
    case '137':
      governanceAddress = '0x34d7b8E14bB7Aae027bd59B6A4aF671A2b48F86B';
      chainlinkV2UsdGasCurrencyPriceFeed = '0xab594600376ec9fd91f8e885dadf0ce036862de0';
      protocolProjectStartsAtOrAfter = 0;
    // hardhat / localhost
    case '31337':
      governanceAddress = deployer.address;
      protocolProjectStartsAtOrAfter = 0;
      break;
  }

  console.log({ governanceAddress, protocolProjectStartsAtOrAfter });

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

  // Deploy a JBMigrationOperator contract.
  const JBMigrationOperator = await deploy('JBMigrationOperator', {
    ...baseDeployArgs,
    args: [JBDirectory.address],
  });

  // Deploy a JBSingleTokenPaymentTerminalStore contract.
  const JBSingleTokenPaymentTerminalStore = await deploy('JBSingleTokenPaymentTerminalStore3_1', {
    ...baseDeployArgs,
    contract:
      'contracts/JBSingleTokenPaymentTerminalStore3_1.sol:JBSingleTokenPaymentTerminalStore3_1',
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

  // Get a reference to USD and GAS_TOKEN currency indexes.
  const USD = await jbCurrenciesLibrary.connect(deployer).USD();
  const GAS_CURRENCY = await jbCurrenciesLibrary.connect(deployer).GAS_CURRENCY();

  // Deploy a JBGasTokenPaymentTerminal contract.
  const JBGasTokenPaymentTerminal = await deploy('JBGasTokenPaymentTerminal3_1', {
    ...baseDeployArgs,
    contract: 'contracts/JBGasTokenPaymentTerminal3_1.sol:JBGasTokenPaymentTerminal3_1',
    args: [
      GAS_CURRENCY,
      JBOperatorStore.address,
      JBProjects.address,
      JBDirectory.address,
      JBSplitStore.address,
      JBPrices.address,
      JBSingleTokenPaymentTerminalStore.address,
      governanceAddress,
    ],
  });

  // Deploy a JBGasTokenERC20ProjectPayerDeployer contract.
  await deploy('JBGasTokenERC20ProjectPayerDeployer', {
    ...baseDeployArgs,
    args: [JBDirectory.address],
  });

  // Deploy a JBGasTokenERC20SplitsPayerDeployer contract.
  await deploy('JBGasTokenERC20SplitsPayerDeployer', {
    ...baseDeployArgs,
    contract: 'contracts/JBGasTokenERC20SplitsPayerDeployer.sol:JBGasTokenERC20SplitsPayerDeployer',
    args: [JBSplitStore.address],
  });

  // Get a reference to an existing GasCurrency/USD feed.
  const usdGasCurrencyFeed = await jbPricesContract.connect(deployer).feedFor(USD, GAS_CURRENCY);

  // If needed, deploy an GasCurrency/USD price feed and add it to the store.
  if (chainlinkV2UsdGasCurrencyPriceFeed && usdGasCurrencyFeed == ethers.constants.AddressZero) {
    // Deploy a JBChainlinkV3PriceFeed contract for GAS_TOKEN/USD.
    const JBChainlinkV3UsdGasCurrencyPriceFeed = await deploy('JBChainlinkV3PriceFeed', {
      ...baseDeployArgs,
      args: [chainlinkV2UsdGasCurrencyPriceFeed],
    });

    //The base currency is GAS_TOKEN since the feed returns the USD price of 1 GAS_TOKEN.
    await jbPricesContract
      .connect(deployer)
      .addFeedFor(USD, GAS_TOKEN, JBChainlinkV3UsdGasCurrencyPriceFeed.address);
  }

  // If needed, transfer the ownership of the JBPrices to to the multisig.
  if ((await jbPricesContract.connect(deployer).owner()) != governanceAddress)
    await jbPricesContract.connect(deployer).transferOwnership(governanceAddress);

  // If needed, transfer the ownership of the JBProjects to to the multisig.
  if ((await jbProjectsContract.connect(deployer).owner()) != governanceAddress)
    await jbProjectsContract.connect(deployer).transferOwnership(governanceAddress);

  let isAllowedToSetFirstController = await jbDirectoryContract
    .connect(deployer)
    .isAllowedToSetFirstController(JBController.address);

  console.log({ isAllowedToSetFirstController });

  // If needed, allow the controller to set projects' first controller, then transfer the ownership of the JBDirectory to the multisig.
  if (!isAllowedToSetFirstController) {
    let tx = await jbDirectoryContract
      .connect(deployer)
      .setIsAllowedToSetFirstController(JBController.address, true);
    await tx.wait();
  }

  // If needed, transfer the ownership of the JBDirectory contract to the multisig.
  if ((await jbDirectoryContract.connect(deployer).owner()) != governanceAddress) {
    let tx = await jbDirectoryContract.connect(deployer).transferOwnership(governanceAddress);
    await tx.wait();
  }

  // Deploy a JB1DayReconfigurationBufferBallot.
  await deploy('JB1DayReconfigurationBufferBallot', {
    ...baseDeployArgs,
    contract: 'contracts/JBReconfigurationBufferBallot.sol:JBReconfigurationBufferBallot',
    args: [86400],
  });

  // Deploy a JB3DayReconfigurationBufferBallot.
  const JB3DayReconfigurationBufferBallot = await deploy('JB3DayReconfigurationBufferBallot', {
    ...baseDeployArgs,
    contract: 'contracts/JBReconfigurationBufferBallot.sol:JBReconfigurationBufferBallot',
    args: [259200],
  });

  // Deploy a JB7DayReconfigurationBufferBallot.
  await deploy('JB7DayReconfigurationBufferBallot', {
    ...baseDeployArgs,
    contract: 'contracts/JBReconfigurationBufferBallot.sol:JBReconfigurationBufferBallot',
    args: [604800],
  });

  // // If needed, deploy the protocol project
  // if ((await jbProjects.connect(deployer).count()) == 0) {
  //   console.log('Adding reserved token splits with current beneficiaries (as of deployment)');

  //   const beneficiaries = [];

  //   let splits = [];

  //   beneficiaries.map((beneficiary) => {
  //     splits.push({
  //       preferClaimed: false,
  //       preferAddToBalance: false,
  //       percent: (1000000000 - 300600000) / beneficiaries.length, // 30.06% for JBDao
  //       projectId: 0,
  //       beneficiary: beneficiary,
  //       lockedUntil: 0,
  //       allocator: ethers.constants.AddressZero,
  //     });
  //   });

  //   splits.push({
  //     preferClaimed: false,
  //     preferAddToBalance: false,
  //     percent: 300600000, // 30.06% for JBDao
  //     projectId: 0,
  //     beneficiary: '0xaf28bcb48c40dbc86f52d459a6562f658fc94b1e',
  //     lockedUntil: 0,
  //     allocator: ethers.constants.AddressZero,
  //   });

  //   let groupedSplits = {
  //     group: 2,
  //     splits: splits,
  //   };

  //   console.log('Deploying protocol project...');

  //   await jbControllerContract.connect(deployer).launchProjectFor(
  //     /*owner*/ governanceAddress,

  //     /* projectMetadata */
  //     [
  //       /*content*/ 'QmQHGuXv7nDh1rxj48HnzFtwvVxwF1KU9AfB6HbfG8fmJF',
  //       /*domain*/ ethers.BigNumber.from(0),
  //     ],

  //     /*fundingCycleData*/
  //     [
  //       /*duration*/ ethers.BigNumber.from(1209600),
  //       /*weight*/ ethers.BigNumber.from('62850518250000000000000'),
  //       /*discountRate*/ ethers.BigNumber.from(5000000),
  //       /*ballot*/ JB3DayReconfigurationBufferBallot.address,
  //     ],

  //     /*fundingCycleMetadata*/
  //     [
  //       /*global*/
  //       [/*allowSetTerminals*/ false, /*allowSetController*/ true, /*pauseTransfer*/ true],
  //       /*reservedRate*/ ethers.BigNumber.from(5000),
  //       /*redemptionRate*/ ethers.BigNumber.from(0),
  //       /*ballotRedemptionRate*/ ethers.BigNumber.from(0),
  //       /*pausePay*/ false,
  //       /*pauseDistributions*/ false,
  //       /*pauseRedeem*/ false,
  //       /*pauseBurn*/ false,
  //       /*allowMinting*/ false,
  //       /*allowTerminalMigration*/ false,
  //       /*allowControllerMigration*/ false,
  //       /*holdFees*/ false,
  //       /*preferClaimedTokenOverride*/ false,
  //       /*useTotalOverflowForRedemptions*/ false,
  //       /*useDataSourceForPay*/ false,
  //       /*useDataSourceForRedeem*/ false,
  //       /*dataSource*/ ethers.constants.AddressZero,
  //       /*metadata*/ 0,
  //     ],

  //     /*mustStartAtOrAfter*/ ethers.BigNumber.from(protocolProjectStartsAtOrAfter),

  //     /*groupedSplits*/[groupedSplits],

  //     /*fundAccessConstraints*/[],

  //     /*terminals*/[JBGasTokenPaymentTerminal.address],

  //     /*memo*/ '',
  //   );
  // }

  console.log('Done');
};

module.exports.tags = ['31'];
