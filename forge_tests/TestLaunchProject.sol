// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// Projects can be launched.
contract TestLaunchProject_Local is TestBaseWorkflow {
    IJBController3_1 private _controller;
    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;
    JBGroupedSplits[] private _groupedSplits;
    JBFundAccessConstraints[] private _fundAccessConstraints;
    IJBPaymentTerminal[] private _terminals;

    function setUp() public override {
        super.setUp();

        _controller = jbController();
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        _data = JBFundingCycleData({
            duration: 0,
            weight: 1000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });
        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: 0,
            baseCurrency: 1,
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
    }

    function testLaunchProject() public {
        // Package a configuration.
        JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Launch a project.
        uint256 projectId =
            _controller.launchProjectFor(msg.sender, _projectMetadata, _cycleConfig, _terminals, "");

        // Get a reference to the first funding cycle.
        JBFundingCycle memory fundingCycle = jbFundingCycleStore().currentOf(projectId);

        // Make sure the funding cycle got saved correctly.
        assertEq(fundingCycle.number, 1);
        assertEq(fundingCycle.weight, _data.weight);
    }

    function testLaunchProjectFuzzWeight(uint256 _weight) public {
        _data = JBFundingCycleData({
            duration: 14,
            weight: _weight,
            discountRate: 450_000_000,
            ballot: IJBFundingCycleBallot(address(0))
        });

        uint256 _projectId;

        JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // expectRevert on the next call if weight overflowing
        if (_weight > type(uint88).max) {
            vm.expectRevert(abi.encodeWithSignature("INVALID_WEIGHT()"));

            _projectId = _controller.launchProjectFor({
                owner: msg.sender,
                projectMetadata: _projectMetadata,
                configurations: _cycleConfig,
                terminals: _terminals,
                memo: ""
            });
        } else {
            _projectId = _controller.launchProjectFor({
                owner: msg.sender,
                projectMetadata: _projectMetadata,
                configurations: _cycleConfig,
                terminals: _terminals,
                memo: ""
            });

            JBFundingCycle memory fundingCycle = jbFundingCycleStore().currentOf(_projectId);

            assertEq(fundingCycle.number, 1);
            assertEq(fundingCycle.weight, _weight);
        }
    }
}
