// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@juicebox/JBController3_0_1.sol";

import "@juicebox/interfaces/IJBController.sol";
import "@juicebox/interfaces/IJBMigratable.sol";
import "@juicebox/interfaces/IJBOperatorStore.sol";
import "@juicebox/interfaces/IJBPaymentTerminal.sol";
import "@juicebox/interfaces/IJBSingleTokenPaymentTerminalStore.sol";
import "@juicebox/interfaces/IJBProjects.sol";

import "@juicebox/interfaces/IJBPayoutRedemptionPaymentTerminal.sol";

import "@juicebox/libraries/JBTokens.sol";
import "@juicebox/libraries/JBCurrencies.sol";
import "@juicebox/libraries/JBFundingCycleMetadataResolver.sol";

import "@paulrberg/contracts/math/PRBMath.sol";
import "@paulrberg/contracts/math/PRBMathUD60x18.sol";

import "forge-std/Test.sol";

/**
 *  @title JBController v3.1 mainnet fork test: rescue distribution limit from controller v3
 *
 *  @notice
 *  This test run on a mainnet fork and the migration scenario:
 *      from a controller 3.1, within the same block:
 *          - change the controller back to the controller v3
 *          - distribute the payouts to the splits
 *          - change the controller to the controller v3.1
 *
 *  Reserved token should stay unchaned, same as v3.1 ability to create new project afterwards
 *  
 *
 *  @dev This test runs on a fork and will NOT be executed by forge test by default (only on CI). To run it locally, you need to run:
 *       `FOUNDRY_PROFILE=CI forge test`
 */
contract TestRescueDistribute_Fork is Test {
    using JBFundingCycleMetadataResolver for JBFundingCycle;

    // Contracts needed
    IJBController oldJbController;
    IJBController newJbController;
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
    uint256 weight = 1 * 10 ** 18;
    uint256 targetInWei = 10 * 10 ** 18;

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth", 16592298); // Block height 2days before new fc
        vm.warp(block.timestamp + 3 days);

        // Collect the mainnet deployment addresses
        jbEthTerminal = IJBPayoutRedemptionPaymentTerminal(
            stdJson.readAddress(vm.readFile("deployments/mainnet/JBETHPaymentTerminal.json"), ".address")
        );
 
        oldJbController =
            IJBController(stdJson.readAddress(vm.readFile("deployments/mainnet/JBController.json"), ".address"));

        // Using the JBController interface, as IJBController3_0_1 only includes new sig.doesn't inherit v3
        newJbController =
            IJBController(stdJson.readAddress(vm.readFile("deployments/mainnet/JBController3_0_1.json"), ".address"));

        jbOperatorStore =
            IJBOperatorStore(stdJson.readAddress(vm.readFile("deployments/mainnet/JBOperatorStore.json"), ".address"));

        jbProjects = oldJbController.projects();
        jbDirectory = oldJbController.directory();
        jbFundingCycleStore = oldJbController.fundingCycleStore();
        jbTokenStore = oldJbController.tokenStore();
        jbSplitsStore = oldJbController.splitsStore();
        jbTerminalStore = jbEthTerminal.store();

        // Some sanity check
        require(jbDirectory == newJbController.directory(), "Setup: directories mismatch");
        require(jbDirectory.controllerOf(1) == address(newJbController), "Setup: new controller mismatch");
        _createFundingCycleData();
    }

    ////////////////////////////////////////////////////////////////////
    //                  setControllerOf(..) flow                      //
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice  Test if 
     * @dev     JuiceboxDAO (id 1) has already allowSetController set.
     */
    function testController31_setController_changeJuiceboxDaoControllerWithoutReconfiguration() public {

        uint256 _fundingTarget = 160_500*10**18;
        address _projectOwner = jbProjects.ownerOf(1);

        uint256 _ethAmountDistributed = _fundingTarget * 10**18 / jbEthTerminal.prices().priceFor(JBCurrencies.USD, JBCurrencies.ETH, 18);

        uint256 _projectBalance = jbTerminalStore.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal)), 1);
        uint256 _terminalBalance = address(jbEthTerminal).balance;
        uint256 _reservedTokenV3_1 = IJBController3_0_1(address(newJbController)).reservedTokenBalanceOf(1);
        uint256 _reservedTokenV3 = oldJbController.reservedTokenBalanceOf(1, _getReservedRate(1));

        // Craft the payload which will:
        // 1) set the project id 1 controller to the v3
        // 2) distribute the payout to the splits
        // 3) set the project id 1 controller to the v3.1

        bytes[] memory _payloads = new bytes[](3);
        address[] memory _targets = new address[](3);

        _payloads[0] = abi.encodeCall(
            jbDirectory.setControllerOf,
            (1,
            address(oldJbController))
        );

        _payloads[1] = abi.encodeCall(
            jbEthTerminal.distributePayoutsOf,
            (
                1, // _projectId
                _fundingTarget, // _amount
                JBCurrencies.USD, // _currency
                JBTokens.ETH, // _token
                0, // _minReturnedTokens
                "" // _memo
            )
        );

        _payloads[2] = abi.encodeCall(
            jbDirectory.setControllerOf,
            (1,
            address(newJbController))
        );

        _targets[0] = address(jbDirectory);
        _targets[1] = address(jbEthTerminal);
        _targets[2] = address(jbDirectory);

        // Deploy the batching contract as a template
        FakeMultisigBatcher _multisig = new FakeMultisigBatcher();

        // Copy/overwrite the project owner address with the batcher code
        vm.etch(_projectOwner, address(_multisig).code);

        // Execute the batch, from the owner
        FakeMultisigBatcher(_projectOwner).exec(_targets, _payloads);

        // ---- Checks -----

        uint256 _projectBalanceAfter = jbTerminalStore.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal)), 1);
        uint256 _terminalBalanceAfter = address(jbEthTerminal).balance;
        uint256 _reservedTokenV3_1After = IJBController3_0_1(address(newJbController)).reservedTokenBalanceOf(1);
        uint256 _reservedTokenV3After = oldJbController.reservedTokenBalanceOf(1, _getReservedRate(1));

        // Check: controller back to the new one?
        assertEq(jbDirectory.controllerOf(1), address(newJbController));

        // Check: project balance decreased in the terminal store (of an amount between all and 0 fee-less recipient)
        assertGe(_projectBalanceAfter, _projectBalance - _ethAmountDistributed);
        assertLe(_projectBalanceAfter, _projectBalance - (_ethAmountDistributed * 975 / 1000));

        // Check: terminal ETH balance decreased?
        assertGe(_terminalBalanceAfter, _terminalBalance - _ethAmountDistributed);
        assertLe(_terminalBalanceAfter, _terminalBalance - (_ethAmountDistributed * 975 / 1000));

        // Check: reserved token balance in the v3.1 unchanged?
        assertEq(_reservedTokenV3_1After, _reservedTokenV3_1);

        // Check: reserved token balance in the v3 unchanged?
        assertEq(_reservedTokenV3After, _reservedTokenV3);
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
            _projectId, data, metadata, 0, _groupedSplits, fundAccessConstraints, ""
        );

        // warp to the next funding cycle
        JBFundingCycle memory fundingCycle = jbFundingCycleStore.currentOf(_projectId);
        vm.warp(fundingCycle.start + (fundingCycle.duration) * 2); // skip 2 fc to avoid ballot

        // Migrate the project to the new controller (no prepForMigration(..) needed anymore)
        vm.prank(_projectOwner);
        oldJbController.migrate(_projectId, jbController);
    }


    function _createFundingCycleData() internal  {
        // Set some mock fc data
        projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

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

    function _getReservedRate(uint256 _projectId) internal returns(uint256) {
        JBFundingCycle memory fundingCycle = jbFundingCycleStore.currentOf(1);
        return fundingCycle.reservedRate();
    }
}


contract FakeMultisigBatcher {
    // This...this has been written by copilot, entirely!
    function exec(address[] memory _targets, bytes[] memory _datas) public {
        for (uint256 i; i < _targets.length; i++) {
            (bool success, ) = _targets[i].call(_datas[i]);
            require(success, "Multitransaction: transaction failed");
        }
    }
}