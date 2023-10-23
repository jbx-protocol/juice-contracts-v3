// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@juicebox/JBController3_1.sol";
import "@juicebox/JBFundAccessConstraintsStore.sol";

import "@juicebox/interfaces/IJBController.sol";
import "@juicebox/interfaces/IJBFundingCycleBallot.sol";
import "@juicebox/interfaces/IJBFundingCycleStore.sol";
import "@juicebox/interfaces/IJBMigratable.sol";
import "@juicebox/interfaces/IJBOperatorStore.sol";
import "@juicebox/interfaces/IJBPaymentTerminal.sol";
import "@juicebox/interfaces/IJBPayoutRedemptionPaymentTerminal.sol";
import "@juicebox/interfaces/IJBPrices.sol";
import "@juicebox/interfaces/IJBProjects.sol";
import "@juicebox/interfaces/IJBSingleTokenPaymentTerminalStore.sol";
import "@juicebox/interfaces/IJBSplitsStore.sol";

import "@juicebox/libraries/JBTokens.sol";
import "@juicebox/libraries/JBCurrencies.sol";
import "@juicebox/libraries/JBFundingCycleMetadataResolver.sol";


import "@juicebox/JBETHPaymentTerminal3_1.sol";
import "@juicebox/JBMigrationOperator.sol";
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

    IJBFundingCycleStore jbFundingCycleStore;
    IJBProjects jbProjects;


    IJBController jbController = IJBController(0x4e3ef8AFCC2B52E4e704f4c8d9B7E7948F651351);
    IJBPayoutRedemptionPaymentTerminal jbEthTerminal = IJBPayoutRedemptionPaymentTerminal(0x7Ae63FBa045Fec7CaE1a75cF7Aa14183483b8397);
    IJBDirectory jbDirectory = IJBDirectory(0xCc8f7a89d89c2AB3559f484E0C656423E979ac9C);

    IJBOperatorStore jbOperatorStore = IJBOperatorStore(0x6F3C5afCa0c9eDf3926eF2dDF17c8ae6391afEfb);

    JBMigrationOperator migrationOperator = JBMigrationOperator(0x004d50E8552f7E811E7DF913A3205ABf48E47b52);

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
    function testMigrationProject13() public {
        vm.createSelectFork("https://rpc.ankr.com/eth", 16939325);

        _initMetadata();

        jbFundingCycleStore = jbController3_1.fundingCycleStore();
        jbProjects = jbController3_1.projects();
        jbDirectory = jbController3_1.directory();
        jbSplitsStore = jbController3_1.splitsStore();

        uint256 _projectId = 13;

        // Set the operator store authorization and reconfigure the funding cycle with correct flags
        address _owner = jbProjects.ownerOf(_projectId);

        // Set the correct permissions in the operator store
        uint256[] memory _permissionIndexes = new uint256[](3);
        _permissionIndexes[0] = JBOperations.MIGRATE_CONTROLLER;
        _permissionIndexes[1] = JBOperations.MIGRATE_TERMINAL;
        _permissionIndexes[2] = JBOperations.SET_TERMINALS;

        vm.prank(_owner);
        jbOperatorStore.setOperator(
            JBOperatorData({
                operator: address(migrationOperator),
                domain: _projectId,
                permissionIndexes: _permissionIndexes
            })
        );

        // Set the correct permissions in the funding cycle metadata
        metadata.allowControllerMigration = true;
        metadata.allowTerminalMigration = true;
        metadata.global.allowSetTerminals = true;

        // Reconfigure the project's fc
        vm.prank(_owner);
        jbController.reconfigureFundingCyclesOf(
            _projectId, data, metadata, 0, groupedSplits, fundAccessConstraints, ""
        );

        // warp to the next funding cycle
        JBFundingCycle memory fundingCycle = jbFundingCycleStore.currentOf(_projectId);

        vm.warp(
            fundingCycle.duration == 0
                ? fundingCycle.ballot != IJBFundingCycleBallot(address(0))
                    ? block.timestamp + fundingCycle.ballot.duration() + 1
                    : block.timestamp + 1
                : fundingCycle.start + fundingCycle.duration * 2 // skip 2 fc to easily avoid ballot
        );


        // uint256 _balanceJbOldTerminal = jbPaymentTerminalStore().balanceOf(IJBSingleTokenPaymentTerminal(address(_oldTerminal)), projectId);
        // uint256 _ETHBalanceJbOldTerminal = address(_oldTerminal).balance;

        // Migrate
        vm.prank(_owner);
        migrationOperator.migrate(
            _projectId, IJBMigratable(jbController3_1), jbEthTerminal3_1, jbEthTerminal
        );

        // // Check: the project must have the new controller
        // assertEq(jbDirectory().controllerOf(projectId), address(_newJbController));

        // // Check: the project must use the new terminal as primary terminal
        // assertEq(
        //     address(jbDirectory().primaryTerminalOf(projectId, JBTokens.ETH)),
        //     address(jbEthTerminal3_1)
        // );
        
        // // Check: The balances and actual ETH must have migrated
        // assertEq(
        //     jbTerminalStore3_1.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal3_1)), projectId),
        //     _balanceJbOldTerminal
        // );
        // assertEq(jbPaymentTerminalStore().balanceOf(IJBSingleTokenPaymentTerminal(address(_oldTerminal)), projectId), 0);

        // assertEq(address(jbEthTerminal3_1).balance, _balanceJbOldTerminal);
        // assertEq(address(_oldTerminal).balance, _ETHBalanceJbOldTerminal - _balanceJbOldTerminal);

        // Test distributing the funds of 
    }

    function _initMetadata() internal {
        projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        data = JBFundingCycleData({
            duration: 14,
            weight: 10 ether,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: 10_000,
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
                distributionLimit: 10 ether,
                overflowAllowance: 5 ether,
                distributionLimitCurrency: 1,
                overflowAllowanceCurrency: 1
            })
        );
    }
}