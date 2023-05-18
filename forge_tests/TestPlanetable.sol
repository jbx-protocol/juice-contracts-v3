// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@juicebox/JBController3_1.sol";
import "@juicebox/JBFundAccessConstraintsStore.sol";

import "@juicebox/interfaces/IJBController.sol";
import "@juicebox/interfaces/IJBMigratable.sol";
import "@juicebox/interfaces/IJBOperatorStore.sol";
import "@juicebox/interfaces/IJBPaymentTerminal.sol";
import "@juicebox/interfaces/IJBSingleTokenPaymentTerminalStore.sol";
import "@juicebox/interfaces/IJBPrices.sol";
import "@juicebox/interfaces/IJBProjects.sol";
import "@juicebox/interfaces/IJBPayoutRedemptionPaymentTerminal.sol";
import "@juicebox/interfaces/IJBFundingCycleStore.sol";
import "@juicebox/interfaces/IJBSplitsStore.sol";

import "@juicebox/libraries/JBTokens.sol";
import "@juicebox/libraries/JBCurrencies.sol";
import "@juicebox/libraries/JBFundingCycleMetadataResolver.sol";

import "@juicebox/JBETHPaymentTerminal3_1.sol";
import "@juicebox/JBSingleTokenPaymentTerminalStore3_1.sol";

import "@paulrberg/contracts/math/PRBMath.sol";
import "@paulrberg/contracts/math/PRBMathUD60x18.sol";

import "forge-std/Test.sol";

/**
 *  @title 
 *
 *  @dev This test runs on a fork and will NOT be executed by forge test by default (only on CI). To run it locally, you need to run:
 *       `FOUNDRY_PROFILE=CI forge test`
 */
contract TestPlanetable_Fork is Test {
    using JBFundingCycleMetadataResolver for JBFundingCycle;

    JBETHPaymentTerminal3_1 jbEthTerminal3_1 = JBETHPaymentTerminal3_1(0xFA391De95Fcbcd3157268B91d8c7af083E607A5C);
    JBController3_1 jbController3_1 = JBController3_1(0x97a5b9D9F0F7cD676B69f584F29048D0Ef4BB59b);

    IJBPayoutRedemptionPaymentTerminal jbEthTerminal;
    IJBFundingCycleStore jbFundingCycleStore;
    IJBProjects jbProjects;
    IJBDirectory jbDirectory;
    JBFundAccessConstraintsStore jbFundsAccessConstraintsStore;
    JBSingleTokenPaymentTerminalStore3_1 jbTerminalStore3_1;
    IJBSplitsStore jbSplitsStore;
    
    // Structure needed
    JBProjectMetadata projectMetadata;
    JBFundingCycleData data;
    JBFundingCycleMetadata metadata;
    JBFundAccessConstraints[] fundAccessConstraints;
    IJBPaymentTerminal[] terminals;
    JBGroupedSplits[] groupedSplits;

    function setUp() public {

    }

    ////////////////////////////////////////////////////////////////////
    //                         Migration                              //
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice  Test the migration of the Planetable project
     * @dev     Should migrate terminal, including funds and set it in directory then distribute
     */
    function testTerminal31_Migration_migratePlanetable() public {
        vm.createSelectFork("https://rpc.ankr.com/eth", 16939325);

        jbFundingCycleStore = jbController3_1.fundingCycleStore();
        jbProjects = jbController3_1.projects();
        jbDirectory = jbController3_1.directory();
        jbSplitsStore = jbController3_1.splitsStore();

        uint256 _projectId = 471;
        jbEthTerminal = IJBPayoutRedemptionPaymentTerminal(address(jbDirectory.primaryTerminalOf(_projectId, JBTokens.GAS_TOKEN)));
        address _projectOwner = jbProjects.ownerOf(_projectId);

        JBFundingCycle memory fundingCycle = jbFundingCycleStore.currentOf(_projectId);

        JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1);
        _groupedSplits[0] = JBGroupedSplits({
            group: 1,
            splits: jbSplitsStore.splitsOf(
                _projectId,
                fundingCycle.configuration, /*domain*/
                JBSplitsGroups.ETH_PAYOUT /*group*/)
        });

        metadata.allowTerminalMigration = true;
        metadata.global.allowSetTerminals = true;

        JBFundAccessConstraints memory fundAccessConstraint;
        fundAccessConstraint.terminal = jbEthTerminal3_1;
        fundAccessConstraint.token = JBTokens.GAS_TOKEN;
        fundAccessConstraint.distributionLimit = 2 ether;
        fundAccessConstraint.distributionLimitCurrency = JBCurrencies.GAS_CURRENCY;
        fundAccessConstraint.overflowAllowance = 0;
        fundAccessConstraint.overflowAllowanceCurrency = JBCurrencies.GAS_CURRENCY;

        fundAccessConstraints.push(fundAccessConstraint);

        // reconfigure
        vm.prank(_projectOwner);
        jbController3_1.reconfigureFundingCyclesOf(
            _projectId, data, metadata, block.timestamp, _groupedSplits, fundAccessConstraints, ""
        );

        // warp to the next funding cycle (3 days ballot)
        vm.warp(
            fundingCycle.start + fundingCycle.duration
        );

        // lez go
        IJBPaymentTerminal[] memory _newTerminal = new IJBPaymentTerminal[](1);
        _newTerminal[0] = IJBPaymentTerminal(address(jbEthTerminal3_1));

        // Can only migrate to one of the project's terminals
        vm.prank(_projectOwner);
        jbDirectory.setTerminalsOf(_projectId, _newTerminal);

        vm.prank(_projectOwner);
        jbEthTerminal.migrate(_projectId, jbEthTerminal3_1);

        // Check: New terminal is the primary?
        assertEq(address(jbDirectory.primaryTerminalOf(_projectId, JBTokens.GAS_TOKEN)), address(jbEthTerminal3_1));

        // Check: distribute?
        uint256 _balanceBefore = _groupedSplits[0].splits[0].beneficiary.balance;
        jbEthTerminal3_1.distributePayoutsOf(_projectId, 2 ether, 1, JBTokens.GAS_TOKEN, 0, '');
        assertApproxEqRel(_balanceBefore + 2 ether, _groupedSplits[0].splits[0].beneficiary.balance, 0.025 ether);
    }

        /**
     * @notice  Test the migration of the Planetable project after the reconfig submitted at block 17034449
     * @dev     Should migrate terminal, including funds and set it in directory then distribute
     */
    function testTerminal31_Migration_migratePlanetableAfterReconfig() public {
        vm.createSelectFork("https://rpc.ankr.com/eth", 17034449);

        jbFundingCycleStore = jbController3_1.fundingCycleStore();
        jbProjects = jbController3_1.projects();
        jbDirectory = jbController3_1.directory();
        jbSplitsStore = jbController3_1.splitsStore();

        uint256 _projectId = 471;
        jbEthTerminal = IJBPayoutRedemptionPaymentTerminal(address(jbDirectory.primaryTerminalOf(_projectId, JBTokens.GAS_TOKEN)));
        address _projectOwner = jbProjects.ownerOf(_projectId);

        JBFundingCycle memory fundingCycle = jbFundingCycleStore.currentOf(_projectId);

        JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1);
        _groupedSplits[0] = JBGroupedSplits({
            group: 1,
            splits: jbSplitsStore.splitsOf(
                _projectId,
                fundingCycle.configuration, /*domain*/
                JBSplitsGroups.ETH_PAYOUT /*group*/)
        });

        // warp to the next funding cycle (3 days ballot)
        vm.warp(
            fundingCycle.start + fundingCycle.duration
        );

        // lez go
        IJBPaymentTerminal[] memory _newTerminal = new IJBPaymentTerminal[](1);
        _newTerminal[0] = IJBPaymentTerminal(address(jbEthTerminal3_1));

        // Can only migrate to one of the project's terminals
        vm.prank(_projectOwner);
        jbDirectory.setTerminalsOf(_projectId, _newTerminal);

        vm.prank(_projectOwner);
        jbEthTerminal.migrate(_projectId, jbEthTerminal3_1);

        // Check: New terminal is the primary?
        assertEq(address(jbDirectory.primaryTerminalOf(_projectId, JBTokens.GAS_TOKEN)), address(jbEthTerminal3_1));

        // Check: distribute?
        uint256 _balanceBefore = _groupedSplits[0].splits[0].beneficiary.balance;
        jbEthTerminal3_1.distributePayoutsOf(_projectId, 2 ether, 1, JBTokens.GAS_TOKEN, 0, '');
        assertApproxEqRel(_balanceBefore + 2 ether, _groupedSplits[0].splits[0].beneficiary.balance, 0.025 ether);
    }
}