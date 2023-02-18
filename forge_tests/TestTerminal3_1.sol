// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@juicebox/JBController3_0_1.sol";

import "@juicebox/interfaces/IJBController.sol";
import "@juicebox/interfaces/IJBMigratable.sol";
import "@juicebox/interfaces/IJBOperatorStore.sol";
import "@juicebox/interfaces/IJBPaymentTerminal.sol";
import "@juicebox/interfaces/IJBSingleTokenPaymentTerminalStore.sol";
import "@juicebox/interfaces/IJBPrices.sol";
import "@juicebox/interfaces/IJBProjects.sol";
import "@juicebox/interfaces/IJBPayoutRedemptionPaymentTerminal.sol";

import "@juicebox/libraries/JBTokens.sol";
import "@juicebox/libraries/JBFundingCycleMetadataResolver.sol";

import "@juicebox/JBETHPaymentTerminal3_1.sol";
import "@juicebox/JBSingleTokenPaymentTerminalStore3_1.sol";

import "@paulrberg/contracts/math/PRBMath.sol";
import "@paulrberg/contracts/math/PRBMathUD60x18.sol";

import "forge-std/Test.sol";

/**
 *  @title JBTerminal v3.1 mainnet fork test
 *
 *  @notice
 *  This test run on a mainnet fork and test the new terminal (v3.1) as well as migration scenarios
 *
 *
 *  This test too the JuiceboxDAO project migration
 *
 *  @dev This test runs on a fork and will NOT be executed by forge test by default (only on CI). To run it locally, you need to run:
 *       `FOUNDRY_PROFILE=CI forge test`
 */
contract TestTerminal31_Fork is Test {
    using JBFundingCycleMetadataResolver for JBFundingCycle;

    // New contract
    JBETHPaymentTerminal3_1 jbEthTerminal3_1;
    JBSingleTokenPaymentTerminalStore3_1 jbTerminalStore3_1;

    // Contracts needed
    IJBController oldJbController;
    IJBDirectory jbDirectory;
    IJBFundingCycleStore jbFundingCycleStore;
    IJBOperatorStore jbOperatorStore;
    IJBPayoutRedemptionPaymentTerminal jbEthTerminal;
    IJBPrices jbPrices;
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
        vm.createSelectFork("https://rpc.ankr.com/eth", 16531301);

        // Collect the mainnet deployment addresses
        jbEthTerminal = IJBPayoutRedemptionPaymentTerminal(
            stdJson.readAddress(vm.readFile("deployments/mainnet/JBETHPaymentTerminal.json"), ".address")
        );
 
        oldJbController =
            IJBController(stdJson.readAddress(vm.readFile("deployments/mainnet/JBController.json"), ".address"));

        jbOperatorStore =
            IJBOperatorStore(stdJson.readAddress(vm.readFile("deployments/mainnet/JBOperatorStore.json"), ".address"));

        jbProjects = oldJbController.projects();
        jbDirectory = oldJbController.directory();
        jbFundingCycleStore = oldJbController.fundingCycleStore();
        jbTokenStore = oldJbController.tokenStore();
        jbSplitsStore = oldJbController.splitsStore();
        jbTerminalStore = jbEthTerminal.store();
        jbPrices = jbEthTerminal.prices();

        jbTerminalStore3_1 = new JBSingleTokenPaymentTerminalStore3_1(
            jbDirectory,
            jbFundingCycleStore,
            jbPrices
        );

        jbEthTerminal3_1 = new JBETHPaymentTerminal3_1(
            jbEthTerminal.baseWeightCurrency(),
            jbOperatorStore,
            jbProjects,
            jbDirectory,
            jbSplitsStore,
            jbPrices,
            jbTerminalStore3_1,
            Ownable(address(jbEthTerminal)).owner()
        );

        _initMetadata();

    }

    ////////////////////////////////////////////////////////////////////
    //                                                //
    ////////////////////////////////////////////////////////////////////

    /**
     * @notice  Test the migration of the JuiceboxDAO terminal (migrate, pay, redeem)
     * @dev     This flow is reproduced
     */
    function testTerminal31_Migration_migrateJuiceboxDAO() public {
        uint256 _balanceJbOldTerminal = jbTerminalStore.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal)), 1);
        uint256 _ETHBalanceJbOldTerminal = address(jbEthTerminal).balance;
        
        _migrateTerminal(1);

        // Check: balances updated?
        assertEq(jbTerminalStore3_1.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal3_1)), 1), _balanceJbOldTerminal);
        assertEq(jbTerminalStore.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal)), 1), 0);

        // Check: ETH actually transfered?
        assertEq(address(jbEthTerminal3_1).balance, _balanceJbOldTerminal);
        assertEq(address(jbEthTerminal).balance, _ETHBalanceJbOldTerminal - _balanceJbOldTerminal);
    }

    // migrate any other project
    function testTerminal31_Migration_migrateOtherProjects(uint256 _projectId) public {
        // Migrate only existing projects
        _projectId = bound(_projectId, 1, jbProjects.count());

        // Migrate only project which are not archived/have a controller
        vm.assume(jbDirectory.controllerOf(_projectId) != address(0));

        uint256 _balanceJbOldTerminal = jbTerminalStore.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal)), _projectId);
        uint256 _ETHBalanceJbOldTerminal = address(jbEthTerminal).balance;
        
        _migrateTerminal(_projectId);

        // Check: balances updated?
        assertEq(jbTerminalStore3_1.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal3_1)), _projectId), _balanceJbOldTerminal);
        assertEq(jbTerminalStore.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal)), _projectId), 0);

        // Check: ETH actually transfered?
        assertEq(address(jbEthTerminal3_1).balance, _balanceJbOldTerminal);
        assertEq(address(jbEthTerminal).balance, _ETHBalanceJbOldTerminal - _balanceJbOldTerminal);
    }

    // use pay on terminal 3.1 issues tokens
    function testTerminal31_Migration_newTerminalIssueTokenWhenPay(uint256 _projectId, uint256 _amount) public {
        address _beneficiary = makeAddr("_beneficiary");
        vm.deal(_beneficiary, 10 ether);

        _amount = bound(_amount, 1, 10 ether);

        // Migrate only existing projects
        _projectId = bound(_projectId, 1, jbProjects.count());

        // Migrate only project which are not archived/have a controller
        vm.assume(jbDirectory.controllerOf(_projectId) != address(0));

        _migrateTerminal(_projectId);

        uint256 _jbTokenBalanceBefore = jbTokenStore.balanceOf(_beneficiary, _projectId);

        // pay terminal
        vm.prank(_beneficiary);
        jbEthTerminal3_1.pay{value: _amount}(
            _projectId,
            _amount,
            address(0),
            _beneficiary,
            /* _minReturnedTokens */
            0,
            /* _preferClaimedTokens */
            false,
            /* _memo */
            "Take my money!",
            /* _delegateMetadata */
            new bytes(0)
        );

        JBFundingCycle memory fundingCycle = jbFundingCycleStore.currentOf(_projectId);
        uint256 _weight = fundingCycle.weight;

        assertEq(jbTokenStore.balanceOf(_beneficiary, _projectId), _jbTokenBalanceBefore + (_amount * _weight / 10**18));
    }

    // Migration jbdao then other projects pay fees to terminal 3.1, even when using other terminal versions (3 and 3.0.1)
    function testTerminal31_Migration_fee_distribution_from_project_on_old_terminal_to_project_on_new_terminal() public {
        // migrate jb dao terminal
        _migrateTerminal(1);

        uint256 _terminalBalanceBeforeFeeDistribution = jbTerminalStore3_1.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal3_1)), 1);

        // Check project JBX balance

        // Distribute
        uint256 _distributionProjectId = 397; // peel project id
        address _projectOwner = jbProjects.ownerOf(_distributionProjectId);
        vm.prank(_projectOwner);
        jbEthTerminal.distributePayoutsOf(
            _distributionProjectId,
            30000 ether,
            2,
            address(0), //token (unused)
            /*min out*/
            0,
            /*LFG*/
            "distribution"
        );

        uint256 _terminalBalanceAfterFeeDistribution = jbTerminalStore3_1.balanceOf(IJBSingleTokenPaymentTerminal(address(jbEthTerminal3_1)), 1);

        // Check project JBX balance -> bigger?
        assertGt(_terminalBalanceAfterFeeDistribution, _terminalBalanceBeforeFeeDistribution);
    }

    // distribution from the new terminal to jbdao

    // use new controller to reconfigure jbdao

    // jbdao can pay other projects, on other terminals




    ////////////////////////////////////////////////////////////////////
    //                            Helpers                             //
    ////////////////////////////////////////////////////////////////////

    function _migrateTerminal(uint256 _projectId) internal {
        address _projectOwner = jbProjects.ownerOf(_projectId);
 
        JBGroupedSplits[] memory _groupedSplits;

        metadata.allowTerminalMigration = true;
        metadata.global.allowSetTerminals = true;

        JBFundingCycle memory fundingCycle = jbFundingCycleStore.currentOf(_projectId);

        // reconfigure
        vm.prank(_projectOwner);
        oldJbController.reconfigureFundingCyclesOf(
            _projectId, data, metadata, block.timestamp, _groupedSplits, fundAccessConstraints, ""
        );

        // warp to the next funding cycle
        vm.warp(
            fundingCycle.duration == 0 ?
                fundingCycle.ballot != IJBFundingCycleBallot(address(0)) ?
                    block.timestamp + fundingCycle.ballot.duration() + 1 :
                    block.timestamp + 1
                : fundingCycle.start + fundingCycle.duration * 2 // skip 2 fc to easily avoid ballot
        );
        
        // lez go
        IJBPaymentTerminal[] memory _newTerminal = new IJBPaymentTerminal[](1);
        _newTerminal[0] = IJBPaymentTerminal(address(jbEthTerminal3_1));

        vm.prank(_projectOwner);
        jbDirectory.setTerminalsOf(_projectId, _newTerminal);

        vm.prank(_projectOwner);
        jbEthTerminal.migrate(_projectId, jbEthTerminal3_1);
    }

    function _initMetadata() internal {

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
}
