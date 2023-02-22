// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import '@juicebox/JBController3_0_1.sol';
import '@juicebox/JBMigrationOperator.sol';
import '@juicebox/JBReconfigurationBufferBallot.sol';

import '@juicebox/interfaces/IJBController.sol';
import '@juicebox/interfaces/IJBMigratable.sol';
import '@juicebox/interfaces/IJBOperatorStore.sol';
import '@juicebox/interfaces/IJBPaymentTerminal.sol';
import '@juicebox/interfaces/IJBSingleTokenPaymentTerminalStore.sol';
import '@juicebox/interfaces/IJBProjects.sol';
import '@juicebox/interfaces/IJBPayoutRedemptionPaymentTerminal.sol';

import '@juicebox/libraries/JBTokens.sol';
import '@juicebox/libraries/JBFundingCycleMetadataResolver.sol';

import '@paulrberg/contracts/math/PRBMath.sol';
import '@paulrberg/contracts/math/PRBMathUD60x18.sol';

import 'forge-std/Test.sol';

import './helpers/TestBaseWorkflow.sol';

/**
 *  @title  Migration operator test
 *
 *  @notice One local and one fork (only ran on foudnry profile CI)
 *
 *  @dev
 */
contract TestMigrationOperator_Local is TestBaseWorkflow {
  uint256 projectId;

  JBController controller;
  JBFundingCycleData data;
  JBProjectMetadata projectMetadata;
  JBFundingCycleMetadata metadata;
  JBGroupedSplits[] groupedSplits; // Default empty
  JBFundAccessConstraints[] fundAccessConstraints; // Default empty
  IJBPaymentTerminal[] terminals; // Default empty

  JBMigrationOperator migrationOperator;

  uint256 BALLOT_DURATION = 3 days;

  function setUp() public override {
    super.setUp();

    controller = jbController();

    projectMetadata = JBProjectMetadata({content: 'myIPFSHash', domain: 1});

    data = JBFundingCycleData({
      duration: 6 days,
      weight: 10000 * 10**18,
      discountRate: 0,
      ballot: JBReconfigurationBufferBallot(address(0))
    });

    metadata = JBFundingCycleMetadata({
      global: JBGlobalFundingCycleMetadata({
        allowSetTerminals: false,
        allowSetController: false,
        pauseTransfers: false
      }),
      reservedRate: 5000,
      redemptionRate: 5000,
      ballotRedemptionRate: 0,
      pausePay: false,
      pauseDistributions: false,
      pauseRedeem: false,
      pauseBurn: false,
      allowMinting: true,
      allowTerminalMigration: false,
      allowControllerMigration: false,
      holdFees: false,
      preferClaimedTokenOverride: false,
      useTotalOverflowForRedemptions: false,
      useDataSourceForPay: false,
      useDataSourceForRedeem: false,
      dataSource: address(0),
      metadata: 0
    });

    terminals = [jbETHPaymentTerminal()];

    projectId = jbController().launchProjectFor(
      multisig(),
      projectMetadata,
      data,
      metadata,
      block.timestamp,
      groupedSplits,
      fundAccessConstraints,
      terminals,
      ''
    );

    // Avoid the same block reconfiguration error
    vm.warp(block.timestamp + 1 days);

    migrationOperator = new JBMigrationOperator(jbDirectory());
  }

  function testMigrationOperator_shouldMigrate() public {
    JBController3_0_1 _newJbController = new JBController3_0_1(
      jbOperatorStore(),
      jbProjects(),
      jbDirectory(),
      jbFundingCycleStore(),
      jbTokenStore(),
      jbSplitsStore()
    );

    JBSingleTokenPaymentTerminalStore3_1 jbTerminalStore3_1 = new JBSingleTokenPaymentTerminalStore3_1(
        jbDirectory(),
        jbFundingCycleStore(),
        jbPrices()
      );

    JBETHPaymentTerminal3_1 jbEthTerminal3_1 = new JBETHPaymentTerminal3_1(
      jbETHPaymentTerminal().baseWeightCurrency(),
      jbOperatorStore(),
      jbProjects(),
      jbDirectory(),
      jbSplitsStore(),
      jbPrices(),
      jbTerminalStore3_1,
      Ownable(address(jbETHPaymentTerminal())).owner()
    );

    uint256[] memory _permissionIndexes = new uint256[](3);
    _permissionIndexes[0] = JBOperations.MIGRATE_CONTROLLER;
    _permissionIndexes[1] = JBOperations.MIGRATE_TERMINAL;
    _permissionIndexes[2] = JBOperations.SET_TERMINALS;

    vm.prank(multisig());
    jbOperatorStore().setOperator(
      JBOperatorData({
        operator: address(migrationOperator),
        domain: projectId,
        permissionIndexes: _permissionIndexes
      })
    );

    metadata.allowControllerMigration = true;
    metadata.allowTerminalMigration = true;
    metadata.global.allowSetTerminals = true;

    vm.prank(multisig());
    jbController().reconfigureFundingCyclesOf(
      projectId,
      data,
      metadata,
      0,
      groupedSplits,
      fundAccessConstraints,
      ''
    );
    // warp to the next funding cycle
    JBFundingCycle memory fundingCycle = jbFundingCycleStore().currentOf(projectId);
    vm.warp(fundingCycle.start + (fundingCycle.duration) + 1);

    vm.prank(multisig());
    migrationOperator.migrate(
      projectId,
      address(_newJbController),
      jbEthTerminal3_1,
      jbETHPaymentTerminal()
    );
  }

  function testMigrationOperator_cannotMigrateIfNotProjectOwner() public {}
}

// TODO:


contract TestMigrationOperator_Fork is Test {
  using JBFundingCycleMetadataResolver for JBFundingCycle;

  // Contracts needed
  IJBController oldJbController;
  IJBDirectory jbDirectory;
  IJBFundingCycleStore jbFundingCycleStore;
  IJBOperatorStore jbOperatorStore;
  IJBPayoutRedemptionPaymentTerminal jbEthTerminal;
  IJBProjects jbProjects;
  IJBSingleTokenPaymentTerminalStore jbTerminalStore;
  IJBSplitsStore jbSplitsStore;
  IJBTokenStore jbTokenStore;

  // Structure needed
  JBProjectMetadata projectMetadata;
  JBFundingCycleData data;
  JBFundingCycleMetadata metadata;
  JBFundAccessConstraints[] fundAccessConstraints;
  IJBPaymentTerminal[] terminals;
  JBGroupedSplits[] groupedSplits;

  // Weight equals to 1 eth
  uint256 weight = 1 * 10**18;
  uint256 targetInWei = 10 * 10**18;

  function setUp() public {
    vm.createSelectFork('https://rpc.ankr.com/eth', 16531301);

    // Collect the mainnet deployment addresses
    jbEthTerminal = IJBPayoutRedemptionPaymentTerminal(
      stdJson.readAddress(vm.readFile('deployments/mainnet/JBETHPaymentTerminal.json'), '.address')
    );

    oldJbController = IJBController(
      stdJson.readAddress(vm.readFile('deployments/mainnet/JBController.json'), '.address')
    );

    jbOperatorStore = IJBOperatorStore(
      stdJson.readAddress(vm.readFile('deployments/mainnet/JBOperatorStore.json'), '.address')
    );

    jbProjects = oldJbController.projects();
    jbDirectory = oldJbController.directory();
    jbFundingCycleStore = oldJbController.fundingCycleStore();
    jbTokenStore = oldJbController.tokenStore();
    jbSplitsStore = oldJbController.splitsStore();
    jbTerminalStore = jbEthTerminal.store();

    // Set some mock fc data
    projectMetadata = JBProjectMetadata({content: 'myIPFSHash', domain: 1});

    data = JBFundingCycleData({
      duration: 14,
      weight: weight,
      discountRate: 0,
      ballot: IJBFundingCycleBallot(address(0))
    });

    metadata = JBFundingCycleMetadata({
      global: JBGlobalFundingCycleMetadata({
        allowSetTerminals: false,
        allowSetController: false,
        pauseTransfers: false
      }),
      reservedRate: 0, // Reserved rate is set in tests, when needed
      redemptionRate: 10000, //100%
      ballotRedemptionRate: 0,
      pausePay: false,
      pauseDistributions: false,
      pauseRedeem: false,
      pauseBurn: false,
      allowMinting: false,
      allowTerminalMigration: false,
      allowControllerMigration: false,
      holdFees: false,
      preferClaimedTokenOverride: false,
      useTotalOverflowForRedemptions: false,
      useDataSourceForPay: false,
      useDataSourceForRedeem: false,
      dataSource: address(0),
      metadata: 0
    });

    terminals.push(jbEthTerminal);

    fundAccessConstraints.push(
      JBFundAccessConstraints({
        terminal: jbEthTerminal,
        token: JBTokens.ETH,
        distributionLimit: targetInWei, // 10 ETH target
        overflowAllowance: 5 ether,
        distributionLimitCurrency: 1, // Currency = ETH
        overflowAllowanceCurrency: 1
      })
    );
  }

  ////////////////////////////////////////////////////////////////////
  //                      migrate(..) flow                          //
  ////////////////////////////////////////////////////////////////////

  /**
   * @notice  Test if a project using the controller V3 can be migrated to the controller V3.1
   * @dev     The project must have a controller, not archived and the allowControllerMigration flag must be set
   */
  function testController31_Migration_migrateAnyExistingProject(uint8 _projectId) public {
    // Migrate only existing projects
    vm.assume(_projectId <= jbProjects.count() && _projectId > 1);

    // Migrate only project which are not archived/have a controller
    vm.assume(jbDirectory.controllerOf(_projectId) != address(0));

    JBController3_0_1 jbController = _migrate(_projectId);

    // Check: the project must have the new controller
    assertEq(jbDirectory.controllerOf(_projectId), address(jbController));
  }

  /**
   * @notice Test if migrating a project with a reserved token will distribute the reserved token before migrating
   */
  function testController31_Migration_distributeReservedTokenBeforeMigrating() external {
    address _projectOwner = makeAddr('_projectOwner');
    address _userWallet = makeAddr('_userWallet');

    uint256 _reservedRate = 4000; // 40%
    uint256 n_reserved_split = 5;

    // Configure the grouped splits
    JBSplit[] memory _split = new JBSplit[](n_reserved_split);
    for (uint256 i = 0; i < n_reserved_split; i++) {
      address _user = vm.addr(i + 1);
      _split[i] = JBSplit({
        preferClaimed: false,
        preferAddToBalance: false,
        percent: JBConstants.SPLITS_TOTAL_PERCENT / n_reserved_split,
        projectId: 0,
        beneficiary: payable(_user),
        lockedUntil: 0,
        allocator: IJBSplitAllocator(address(0))
      });
    }
    JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1);
    _groupedSplits[0] = JBGroupedSplits({group: JBSplitsGroups.RESERVED_TOKENS, splits: _split});

    // Create a project with a reserved rate to insure the project has undistributed reserved tokens
    metadata.reservedRate = _reservedRate;
    uint256 _projectId = oldJbController.launchProjectFor(
      _projectOwner,
      projectMetadata,
      data,
      metadata,
      block.timestamp,
      _groupedSplits,
      fundAccessConstraints,
      terminals,
      ''
    );

    // Avoid overwriting the fc when reconfiguring the project
    vm.warp(block.timestamp + 1);

    // Pay the project, 40% are reserved
    uint256 payAmountInWei = 10 ether;
    jbEthTerminal.pay{value: payAmountInWei}(
      _projectId,
      payAmountInWei,
      address(0),
      _userWallet,
      /* _minReturnedTokens */
      0,
      /* _preferClaimedTokens */
      false,
      /* _memo */
      'Take my money!',
      /* _delegateMetadata */
      new bytes(0)
    );

    // Check: Weight is 1-1, so the reserved tokens are 40% of the gross pay amount
    assertEq(
      oldJbController.reservedTokenBalanceOf(_projectId, _reservedRate),
      (payAmountInWei * _reservedRate) / JBConstants.MAX_RESERVED_RATE
    );

    // Migrate the controller to v3_1
    JBController3_0_1 jbController = _migrateWithGroupedsplits(_projectId, _groupedSplits);

    // Check: Assert that the reserved tokens have been distributed and can no longer be distributed
    assertEq(oldJbController.reservedTokenBalanceOf(_projectId, _reservedRate), 0);
    assertEq(jbController.reservedTokenBalanceOf(_projectId), 0);

    // Check: Assert that all users in the split received their share
    for (uint256 i = 0; i < n_reserved_split; i++) {
      address _user = vm.addr(i + 1);
      assertEq(
        jbController.tokenStore().unclaimedBalanceOf(_user, _projectId),
        (payAmountInWei * _reservedRate) / JBConstants.MAX_RESERVED_RATE / n_reserved_split
      );
    }
  }

  /**
   * @notice Test if a project using the controller V3.1 has the reserved token balance adequalty tracked
   */
  function testController31_Migration_tracksReservedTokenInNewController(uint8 _projectId)
    external
  {
    // Migrate only existing projects
    vm.assume(_projectId <= jbProjects.count() && _projectId > 1);

    // Migrate only project which are not archived/have a controller
    vm.assume(jbDirectory.controllerOf(_projectId) != address(0));

    address _userWallet = makeAddr('_userWallet');

    metadata.reservedRate = 4000; // 40%

    JBController3_0_1 jbController = _migrate(_projectId);

    // No reserved token before any transaction
    assertEq(jbController.reservedTokenBalanceOf(_projectId), 0);

    // Pay the project, 40% are reserved
    uint256 payAmountInWei = 10 ether;
    jbEthTerminal.pay{value: payAmountInWei}(
      _projectId,
      payAmountInWei,
      address(0),
      _userWallet,
      /* _minReturnedTokens */
      1,
      /* _preferClaimedTokens */
      false,
      /* _memo */
      'Take my money!',
      /* _delegateMetadata */
      new bytes(0)
    );

    // Check: Weight is 1-1, so the reserved tokens are 40% of the gross pay amount
    assertEq(
      jbController.reservedTokenBalanceOf(_projectId),
      (payAmountInWei * 4000) / JBConstants.MAX_RESERVED_RATE
    );
  }

  /**
   * @notice  Test if the new controller might launch new projects
   * @dev     The controller need to be allowed to set a new controller in new projects, in JBDirectory
   */
  function testController31_Migration_launchNewProjectViaNewController(uint256 _reservedRate)
    external
  {
    // Pass only valid reserved rates
    _reservedRate = bound(_reservedRate, 0, JBConstants.MAX_RESERVED_RATE);

    address _userWallet = makeAddr('_userWallet');
    address _projectOwner = makeAddr('projectOwner');
    address _protocolOwner = jbProjects.ownerOf(1);

    // Create a new controller
    JBController3_0_1 _jbController = new JBController3_0_1(
      jbOperatorStore,
      jbProjects,
      jbDirectory,
      jbFundingCycleStore,
      jbTokenStore,
      jbSplitsStore
    );

    // Grant the permission to the new controller to launch a project, in the directory
    vm.prank(_protocolOwner);
    jbDirectory.setIsAllowedToSetFirstController(address(_jbController), true);

    // Create a project with a reserved rate to insure the project has undistributed reserved tokens
    metadata.reservedRate = _reservedRate;

    uint256 _projectId = _jbController.launchProjectFor(
      _projectOwner,
      projectMetadata,
      data,
      metadata,
      block.timestamp,
      groupedSplits,
      fundAccessConstraints,
      terminals,
      ''
    );

    // Check: Assert that the project has been created
    assertTrue(_projectId > 0);

    // Pay the project, 40% are reserved
    uint256 payAmountInWei = 10 ether;
    jbEthTerminal.pay{value: payAmountInWei}(
      _projectId,
      payAmountInWei,
      address(0),
      _userWallet,
      /* _minReturnedTokens */
      0,
      /* _preferClaimedTokens */
      false,
      /* _memo */
      'Take my money!',
      /* _delegateMetadata */
      new bytes(0)
    );

    // Check: Weight is 1-1, so the reserved tokens are 40% of the gross pay amount
    assertEq(
      _jbController.reservedTokenBalanceOf(_projectId),
      (payAmountInWei * _reservedRate) / JBConstants.MAX_RESERVED_RATE
    );
  }

  ////////////////////////////////////////////////////////////////////
  //                  setControllerOf(..) flow                      //
  ////////////////////////////////////////////////////////////////////

  /**
   * @notice  Test if the controller v3.1 can be set as the controller of an existing project
   * @dev     The project must have a controller, not archived and the allowSetController flag must be set
   */
  function testController31_setController_changeTheControllerForAnyProject(uint8 _projectId)
    public
  {
    // Migrate only existing projects
    vm.assume(_projectId <= jbProjects.count() && _projectId > 1);

    // Migrate only project which are not archived/have a controller
    vm.assume(jbDirectory.controllerOf(_projectId) != address(0));

    // Create a new controller
    JBController3_0_1 _jbController = new JBController3_0_1(
      jbOperatorStore,
      jbProjects,
      jbDirectory,
      jbFundingCycleStore,
      jbTokenStore,
      jbSplitsStore
    );

    address _projectOwner = jbProjects.ownerOf(_projectId);

    // Allow controller migration in the fc
    metadata.global.allowSetController = true;

    // Reconfigure the fc
    vm.prank(_projectOwner);
    oldJbController.reconfigureFundingCyclesOf(
      _projectId,
      data,
      metadata,
      0,
      groupedSplits,
      fundAccessConstraints,
      ''
    );

    // warp to the next funding cycle
    JBFundingCycle memory fundingCycle = jbFundingCycleStore.currentOf(_projectId);
    vm.warp(fundingCycle.start + (fundingCycle.duration) * 2); // skip 2 fc to avoid potential ballot

    // Change the controller
    vm.prank(_projectOwner);
    jbDirectory.setControllerOf(_projectId, address(_jbController));
  }

  /**
   * @notice  Test if the controller v3.1 can be set as the controller of JuiceboxDAO
   * @dev     JuiceboxDAO (id 1) has already allowSetController set.
   */
  function testController31_setController_changeJuiceboxDaoControllerWithoutReconfiguration()
    public
  {
    // Set the block height, as this change will occur in the future - need an archive node
    vm.rollFork(16536403);

    // Create a new controller
    JBController3_0_1 _jbController = new JBController3_0_1(
      jbOperatorStore,
      jbProjects,
      jbDirectory,
      jbFundingCycleStore,
      jbTokenStore,
      jbSplitsStore
    );

    address _projectOwner = jbProjects.ownerOf(1);

    // Change the controller
    vm.prank(_projectOwner);
    jbDirectory.setControllerOf(1, address(_jbController));
  }

  function _migrate(uint256 _projectId) internal returns (JBController3_0_1 jbController) {
    return _migrateWithGroupedsplits(_projectId, new JBGroupedSplits[](0));
  }

  /**
   * @notice  Create a new controller, set a new fc with the allowControllerMigration flag set to true
   *          then warp and migrate the project to the new controller
   * @param   _projectId      The id of the project to migrate
   * @param   _groupedSplits  A grouped splits for the reserved tokens
   * @return  jbController    The new controller
   */
  function _migrateWithGroupedsplits(uint256 _projectId, JBGroupedSplits[] memory _groupedSplits)
    internal
    returns (JBController3_0_1 jbController)
  {
    // Create a new controller
    jbController = new JBController3_0_1(
      jbOperatorStore,
      jbProjects,
      jbDirectory,
      jbFundingCycleStore,
      jbTokenStore,
      jbSplitsStore
    );

    address _projectOwner = jbProjects.ownerOf(_projectId);

    // Allow controller migration in the fc
    metadata.allowControllerMigration = true;

    vm.prank(_projectOwner);
    oldJbController.reconfigureFundingCyclesOf(
      _projectId,
      data,
      metadata,
      0,
      _groupedSplits,
      fundAccessConstraints,
      ''
    );

    // warp to the next funding cycle
    JBFundingCycle memory fundingCycle = jbFundingCycleStore.currentOf(_projectId);
    vm.warp(fundingCycle.start + (fundingCycle.duration) * 2); // skip 2 fc to avoid ballot

    // Migrate the project to the new controller (no prepForMigration(..) needed anymore)
    vm.prank(_projectOwner);
    oldJbController.migrate(_projectId, jbController);
  }
}
