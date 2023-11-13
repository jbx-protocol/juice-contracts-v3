// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";
import {MockPriceFeed} from './mock/MockPriceFeed.sol';

// A funding cycle's weight can be cached to make larger intervals tractible under the gas limit.
contract TestFundingCycleWeightCaching_Local is TestBaseWorkflow {
    uint256 private constant _GAS_LIMIT = 30_000_000;
    uint8 private constant _WEIGHT_DECIMALS = 18; // FIXED 
    uint256 private constant _DURATION = 1;
    uint256 private constant _DISCOUNT_RATE = 1;
    
    IJBController3_1 private _controller;
    IJBFundingCycleStore private _fundingCycleStore;
    address private _projectOwner;
    
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _fundingCycleStore = jbFundingCycleStore();
        _controller = jbController();
        _data = JBFundingCycleData({
            duration: _DURATION,
            weight: 1000 * 10 ** _WEIGHT_DECIMALS,
            discountRate: _DISCOUNT_RATE,
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
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalOverflowForRedemptions: true,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(0),
            metadata: 0
        });
    }
    
    /// Test that caching a cycle's weight yields the same result as computing it.
    function testWeightCaching(uint256 _cycleDiff) public {
        // Bound to 8x the discount multiple cache threshold.
        _cycleDiff = bound(_cycleDiff, 0, 80000);

        // Keep references to the projects.
        uint256 _projectId1;
        uint256 _projectId2;

        // Package up the configuration info.
        JBFundingCycleConfig[] memory _cycleConfigurations = new JBFundingCycleConfig[](1);

        {
            _cycleConfigurations[0].mustStartAtOrAfter = 0;
            _cycleConfigurations[0].data = _data;
            _cycleConfigurations[0].metadata = _metadata;
            _cycleConfigurations[0].groupedSplits = new JBGroupedSplits[](0);
            _cycleConfigurations[0].fundAccessConstraints = new JBFundAccessConstraints[](0);

            // Create the project to test.
            _projectId1 = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
                fundingCycleConfigurations: _cycleConfigurations,
                terminalConfigurations: new JBTerminalConfig[](0),
                memo: ""
            });

            // Create the project to test.
            _projectId2 = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
                fundingCycleConfigurations: _cycleConfigurations,
                terminalConfigurations: new JBTerminalConfig[](0),
                memo: ""
            });
        }

        // Keep a reference to the current funding cycles.
        JBFundingCycle memory _fundingCycle1 = jbFundingCycleStore().currentOf(_projectId1);
        JBFundingCycle memory _fundingCycle2 = jbFundingCycleStore().currentOf(_projectId2);

        // Go a few rolled over cycles into the future.
        vm.warp(block.timestamp + (_DURATION * 10));

        // Keep a reference to the amount of gas before the caching call.
        uint256 _gasBeforeCache = gasleft();

        // Cache the weight in the second project.
        _fundingCycleStore.updateFundingCycleWeightCache(_projectId2);

        // Keep a reference to the amout of gas spent on the call.
        uint256 _gasDiffCache = _gasBeforeCache - gasleft();

        // Make sure the diff is within the limit
        assertLe(_gasDiffCache, _GAS_LIMIT);

        // Go many rolled over cycles into the future.
        vm.warp(block.timestamp + (_DURATION * _cycleDiff));

        // Cache the weight in the second project again.
        _fundingCycleStore.updateFundingCycleWeightCache(_projectId2);

        // Inherit the weight.
        _cycleConfigurations[0].data.weight = 0;

        // Keep a reference to the amount of gas before the call.
        uint256 _gasBefore1 = gasleft();

        // Reconfigure the cycle.
        vm.startPrank(_projectOwner);
        _controller.reconfigureFundingCyclesOf({
            projectId: _projectId1,
            fundingCycleConfigurations: _cycleConfigurations,
            memo: ""
        });

        // Keep a reference to the amout of gas spent on the call.
        uint256 _gasDiff1 = _gasBefore1 - gasleft();

        // Make sure the diff is within the limit
        assertLe(_gasDiff1, _GAS_LIMIT);

        // Keep a reference to the amount of gas before the call.
        uint256 _gasBefore2 = gasleft();

        _controller.reconfigureFundingCyclesOf({
            projectId: _projectId2,
            fundingCycleConfigurations: _cycleConfigurations,
            memo: ""
        });
        vm.stopPrank();

        // Keep a reference to the amout of gas spent on the call.
        uint256 _gasDiff2 = _gasBefore2 - gasleft();

        // Make sure the diff is within the limit
        assertLe(_gasDiff2, _GAS_LIMIT);

        // Renew the reference to the current funding cycle.
        _fundingCycle1 = jbFundingCycleStore().currentOf(_projectId1);
        _fundingCycle2 = jbFundingCycleStore().currentOf(_projectId2);

        // The cached call should have been cheaper.
        assertLe(_gasDiff2, _gasDiff1);

        // Make sure the funding cycle's have the same weight.
        assertEq(_fundingCycle1.weight, _fundingCycle2.weight);

        // Cache the weight in the second project again.
        _fundingCycleStore.updateFundingCycleWeightCache(_projectId2);

        // Go many rolled over cycles into the future.
        vm.warp(block.timestamp + (_DURATION * _cycleDiff));

        // Reconfigure the cycle.
        vm.prank(_projectOwner);
        _controller.reconfigureFundingCyclesOf({
            projectId: _projectId2,
            fundingCycleConfigurations: _cycleConfigurations,
            memo: ""
        });
    }
}