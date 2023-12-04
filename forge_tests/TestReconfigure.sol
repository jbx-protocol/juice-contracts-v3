// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// A project's funding cycle's can be scheduled, and rescheduled so long as the provided reconfiguration ballot is approved.
contract TestReconfigureProject_Local is TestBaseWorkflow {
    IJBController3_1 private _controller;
    JBFundingCycleData private _data;
    JBFundingCycleData private _dataReconfiguration;
    JBFundingCycleMetadata private _metadata;
    JBReconfigurationBufferBallot private _ballot;
    JBGroupedSplits[] private _groupedSplits;
    JBFundAccessConstraints[] private _fundAccessConstraints;
    IJBTerminal private _terminal;

    uint256 private _BALLOT_DURATION = 3 days;
    uint256 private _CYCLE_DURATION = 6;

    function setUp() public override {
        super.setUp();

        _terminal = jbPayoutRedemptionTerminal();
        _controller = jbController();

        _ballot = new JBReconfigurationBufferBallot(_BALLOT_DURATION);
        _data = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 1000 * 10 ** 18,
            discountRate: 0,
            ballot: _ballot
        });
        _dataReconfiguration = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 69 * 10 ** 18,
            discountRate: 0,
            ballot: JBReconfigurationBufferBallot(address(0))
        });

        _metadata = JBFundingCycleMetadata({
            reservedRate: 0,
            redemptionRate: 0,
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
            pauseTokenCreditTransfers: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowControllerMigration: false,
            allowSetController: false,
            holdFees: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(0),
            metadata: 0
        });
    }

    function launchProjectForTest() public returns (uint256) {
        // Package up cycle config.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
        _cycleConfig[0].fundAccessConstraints = new JBFundAccessConstraints[](0);

        // Package up terminal config.
        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        uint256 projectId = _controller.launchProjectFor({
            owner: address(multisig()),
            projectMetadata: "myIPFSHash",
            rulesetConfigurations: _rulesetConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        return projectId;
    }

    function testReconfigureProject() public {
        // Package a funding cycle configuration.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Deploy a project.
        uint256 projectId = launchProjectForTest();

        // Keep a reference to the current funding cycle.
        JBFundingCycle memory _fundingCycle = jbFundingCycleStore().currentOf(projectId);

        // Make sure the cycle has a number of 1.
        assertEq(_fundingCycle.number, 1);
        // Make sure the cycle's weight matches.
        assertEq(_fundingCycle.weight, _data.weight);

        // Keep a reference to the cycle's configuration.
        uint256 _currentConfiguration = _fundingCycle.configuration;

        // Increment the weight to create a difference.
        _cycleConfig[0].data.weight = _cycleConfig[0].data.weight + 1;

        // Add a cycle.
        vm.prank(multisig());
        _controller.reconfigureFundingCyclesOf(projectId, _cycleConfig, "");

        // Make sure the current cycle hasn't changed.
        _fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(_fundingCycle.number, 1);
        assertEq(_fundingCycle.configuration, _currentConfiguration);
        assertEq(_fundingCycle.weight, _data.weight);

        // Go to the start of the next cycle.
        vm.warp(_fundingCycle.start + _fundingCycle.duration);

        // Get the current cycle.
        JBFundingCycle memory _newFundingCycle = jbFundingCycleStore().currentOf(projectId);
        // It should be the second cycle.
        assertEq(_newFundingCycle.number, 2);
        assertEq(_newFundingCycle.weight, _data.weight + 1);
        assertEq(_newFundingCycle.basedOn, _currentConfiguration);
    }

    function testMultipleReconfigurationOnRolledOver() public {
        // Keep references to two different weights.
        uint256 _weightFirstReconfiguration = 1234 * 10 ** 18;
        uint256 _weightSecondReconfiguration = 6969 * 10 ** 18;

        // Launch a project.
        uint256 projectId = launchProjectForTest();

        // Keep a reference to the current funding cycle.
        JBFundingCycle memory _fundingCycle = jbFundingCycleStore().currentOf(projectId);

        // Make sure the cycle is correct.
        assertEq(_fundingCycle.number, 1);
        assertEq(_fundingCycle.weight, _data.weight);

        // Keep a reference to teh current configuration.
        uint256 _currentConfiguration = _fundingCycle.configuration;

        // Jump to the next funding cycle.
        vm.warp(block.timestamp + _fundingCycle.duration);

        // Package up a reconfiguration.
        JBFundingCycleConfig[] memory _firstReconfig = new JBFundingCycleConfig[](1);
        _firstReconfig[0].mustStartAtOrAfter = 0;
        _firstReconfig[0].data = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightFirstReconfiguration,
            discountRate: 0,
            ballot: _ballot
        }); // 3days ballot;
        _firstReconfig[0].metadata = _metadata;
        _firstReconfig[0].groupedSplits = _groupedSplits;
        _firstReconfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Reconfigure
        vm.prank(multisig());
        _controller.reconfigureFundingCyclesOf(projectId, _firstReconfig, "");

        // Package up another reconfiguration.
        JBFundingCycleConfig[] memory _secondReconfig = new JBFundingCycleConfig[](1);
        _secondReconfig[0].mustStartAtOrAfter = 0;
        _secondReconfig[0].data = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightSecondReconfiguration,
            discountRate: 0,
            ballot: _ballot
        }); // 3days ballot;
        _secondReconfig[0].metadata = _metadata;
        _secondReconfig[0].groupedSplits = _groupedSplits;
        _secondReconfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Reconfigure again
        vm.prank(multisig());
        _controller.reconfigureFundingCyclesOf(projectId, _secondReconfig, "");

        // Since the second reconfiguration happened during the same block as the one prior, increment the config.
        uint256 secondReconfiguration = block.timestamp + 1;

        // The current funding cycle should not have changed, still in FC#2, rolled over from FC#1.
        _fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(_fundingCycle.number, 2);
        assertEq(_fundingCycle.configuration, _currentConfiguration);
        assertEq(_fundingCycle.weight, _data.weight);

        // Jump to after the ballot passed, but before the next FC
        vm.warp(_fundingCycle.start + _fundingCycle.duration - 1);

        // Make sure the queued fuding cycle is the second reconfiguration
        JBFundingCycle memory queuedFundingCycle = jbFundingCycleStore().queuedOf(projectId);
        assertEq(queuedFundingCycle.number, 3);
        assertEq(queuedFundingCycle.configuration, secondReconfiguration);
        assertEq(queuedFundingCycle.weight, _weightSecondReconfiguration);

        // Go the the start of the queued cycle.
        vm.warp(_fundingCycle.start + _fundingCycle.duration);

        // Make sure the second reconfiguration is now the current one
        JBFundingCycle memory _newFundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(_newFundingCycle.number, 3);
        assertEq(_newFundingCycle.configuration, secondReconfiguration);
        assertEq(_newFundingCycle.weight, _weightSecondReconfiguration);
    }

    function testMultipleReconfigure(uint8 _ballotDuration) public {
        // Create a ballot with the provided approval duration threshold.
        _ballot = new JBReconfigurationBufferBallot(_ballotDuration);

        // Package the funding cycle configuration data.
        _data = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 10_000 ether,
            discountRate: 0,
            ballot: _ballot
        });
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Launch a project to test.
        uint256 projectId = launchProjectForTest();

        // Keep a reference to the initial, current, and queued cycles.
        JBFundingCycle memory initialFundingCycle = jbFundingCycleStore().currentOf(projectId);
        JBFundingCycle memory currentFundingCycle = initialFundingCycle;
        JBFundingCycle memory queuedFundingCycle = jbFundingCycleStore().queuedOf(projectId);

        for (uint256 i = 0; i < _CYCLE_DURATION + 1; i++) {
            // If the ballot is less than the cycle's duration, make sure the current cycle's weight is linearly decremented.
            if (_ballotDuration + i * 1 days < currentFundingCycle.duration) {
                assertEq(currentFundingCycle.weight, initialFundingCycle.weight - i);
            }

            // Package up a new funding cycle with decremented weight.
            _data = JBFundingCycleData({
                duration: _CYCLE_DURATION * 1 days,
                weight: initialFundingCycle.weight - (i + 1), // i+1 -> next funding cycle
                discountRate: 0,
                ballot: _ballot
            });
            JBFundingCycleConfig[] memory _reconfig = new JBFundingCycleConfig[](1);
            _reconfig[0].mustStartAtOrAfter = 0;
            _reconfig[0].data = _data;
            _reconfig[0].metadata = _metadata;
            _reconfig[0].groupedSplits = _groupedSplits;
            _reconfig[0].fundAccessConstraints = _fundAccessConstraints;

            // Submit the reconfiguration.
            vm.prank(multisig());
            _controller.reconfigureFundingCyclesOf(projectId, _reconfig, "");

            // Get a refernce to the current and queued funding cycles.
            currentFundingCycle = jbFundingCycleStore().currentOf(projectId);
            queuedFundingCycle = jbFundingCycleStore().queuedOf(projectId);

            // Make sure the queued cycle is the funding cycle currently under ballot.
            assertEq(queuedFundingCycle.weight, _data.weight);

            // If the full ballot duration included in the funding cycle.
            if (
                _ballotDuration == 0
                    || currentFundingCycle.duration % (_ballotDuration + i * 1 days)
                        < currentFundingCycle.duration
            ) {
                // Make sure the current cycle's weight is still linearly decremented.
                assertEq(currentFundingCycle.weight, initialFundingCycle.weight - i);

                // Shift forward the start of the ballot into the fc, one day at a time, from fc to fc
                vm.warp(currentFundingCycle.start + currentFundingCycle.duration + i * 1 days);

                // Make sure what was the queued cycle is now current.
                currentFundingCycle = jbFundingCycleStore().currentOf(projectId);
                assertEq(currentFundingCycle.weight, _data.weight);

                // Make sure queued is the rolled-over version of current.
                queuedFundingCycle = jbFundingCycleStore().queuedOf(projectId);
                assertEq(queuedFundingCycle.weight, _data.weight);
            }
            // If the ballot is accross many funding cycles.
            else {
                // Make sure the current funding cycle has rolled over.
                vm.warp(currentFundingCycle.start + currentFundingCycle.duration);
                assertEq(currentFundingCycle.weight, initialFundingCycle.weight - i);

                // Make sure the new funding cycle has started once the ballot duration has passed.
                vm.warp(currentFundingCycle.start + currentFundingCycle.duration + _ballotDuration);
                currentFundingCycle = jbFundingCycleStore().currentOf(projectId);
                assertEq(currentFundingCycle.weight, _data.weight);
            }
        }
    }

    function testLaunchProjectWrongBallot() public {
        /// Pacakge the configuration.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Launch the project.
        uint256 projectId = launchProjectForTest();

        // Package another with a bad ballot.
        JBFundingCycleData memory _dataNew = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 12_345 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(6969)) // Wrong ballot address
        });

        vm.prank(multisig());
        vm.expectRevert(abi.encodeWithSignature("INVALID_BALLOT()"));

        JBFundingCycleConfig[] memory _reconfig = new JBFundingCycleConfig[](1);
        _reconfig[0].mustStartAtOrAfter = 0;
        _reconfig[0].data = _dataNew;
        _reconfig[0].metadata = _metadata;
        _reconfig[0].groupedSplits = _groupedSplits;
        _reconfig[0].fundAccessConstraints = _fundAccessConstraints;

        _controller.reconfigureFundingCyclesOf(projectId, _reconfig, "");
    }

    function testReconfigureShortDurationProject() public {
        uint256 _shortDuration = 5 minutes;

        // Package a funding cycle reconfiguration.
        _data = JBFundingCycleData({
            duration: _shortDuration,
            weight: 10_000 * 10 ** 18,
            discountRate: 0,
            ballot: _ballot
        });
        _dataReconfiguration = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 69 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Launch a project to test.
        uint256 projectId = launchProjectForTest();

        // Get a reference to the current funding cycle.
        JBFundingCycle memory _fundingCycle = jbFundingCycleStore().currentOf(projectId);

        // Make sure the current funding cycle is correct.
        assertEq(_fundingCycle.number, 1); // ok
        assertEq(_fundingCycle.weight, _data.weight);

        // Keep a reference to the current configuration.
        uint256 _currentConfiguration = _fundingCycle.configuration;

        // Package up a reconfiguration.
        JBFundingCycleConfig[] memory _reconfig = new JBFundingCycleConfig[](1);
        _reconfig[0].mustStartAtOrAfter = 0;
        _reconfig[0].data = _dataReconfiguration;
        _reconfig[0].metadata = _metadata;
        _reconfig[0].groupedSplits = _groupedSplits;
        _reconfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Submit the reconfiguration.
        vm.prank(multisig());
        _controller.reconfigureFundingCyclesOf(projectId, _reconfig, "");

        // Make sure the cycle hasn't changed.
        _fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(_fundingCycle.number, 1);
        assertEq(_fundingCycle.configuration, _currentConfiguration);
        assertEq(_fundingCycle.weight, _data.weight);

        // Go the the second cycle.
        vm.warp(_fundingCycle.start + _fundingCycle.duration);

        // Make sure the cycle rolled over.
        JBFundingCycle memory _newFundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(_newFundingCycle.number, 2);
        assertEq(_newFundingCycle.weight, _data.weight);

        // Go to the end of the ballot.
        vm.warp(_fundingCycle.start + _fundingCycle.duration + _BALLOT_DURATION);

        // Make sure the reconfiguration is in effect.
        _newFundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(
            _newFundingCycle.number, _fundingCycle.number + (_BALLOT_DURATION / _shortDuration) + 1
        );
        assertEq(_newFundingCycle.weight, _dataReconfiguration.weight);
    }

    function testReconfigureWithoutBallot() public {
        // Package a reconfiguration.
        _data = JBFundingCycleData({
            duration: 5 minutes,
            weight: 10_000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });
        _dataReconfiguration = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 69 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Launch a project to test with.
        uint256 projectId = launchProjectForTest();

        // Get a reference to the current funding cycle.
        JBFundingCycle memory _fundingCycle = jbFundingCycleStore().currentOf(projectId);

        // Make sure the cycle is expected.
        assertEq(_fundingCycle.number, 1);
        assertEq(_fundingCycle.weight, _data.weight);

        // Package a reconfiguration.
        JBFundingCycleConfig[] memory _reconfig = new JBFundingCycleConfig[](1);

        _reconfig[0].mustStartAtOrAfter = 0;
        _reconfig[0].data = _dataReconfiguration;
        _reconfig[0].metadata = _metadata;
        _reconfig[0].groupedSplits = _groupedSplits;
        _reconfig[0].fundAccessConstraints = _fundAccessConstraints;

        vm.prank(multisig());
        _controller.reconfigureFundingCyclesOf(projectId, _reconfig, "");

        // Make sure the cycle hasn't changed.
        _fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(_fundingCycle.number, 1);
        assertEq(_fundingCycle.weight, _data.weight);

        // Make sure the cycle has changed once the cycle is over.
        vm.warp(_fundingCycle.start + _fundingCycle.duration);
        _fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(_fundingCycle.number, 2);
        assertEq(_fundingCycle.weight, _dataReconfiguration.weight);
    }

    function testMixedStarts() public {
        // Keep references to our different weights for assertions
        uint256 _weightInitial = 1000 * 10 ** 18;
        uint256 _weightFirstReconfiguration = 1234 * 10 ** 18;
        uint256 _weightSecondReconfiguration = 6969 * 10 ** 18;

        // Keep a reference to the expected configuration timestamps
        uint256 _initialTimestamp = block.timestamp;

        // Package up a reconfiguration.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightInitial,
            discountRate: 0,
            ballot: _ballot
        }); // 3days ballot;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Launch the project to test with.
        uint256 projectId = launchProjectForTest();

        // Send the reconfiguration.
        JBFundingCycle memory _fundingCycle = jbFundingCycleStore().currentOf(projectId);

        // Make sure the first cycle has begun.
        assertEq(_fundingCycle.number, 1);
        assertEq(_fundingCycle.weight, _weightInitial);
        assertEq(_fundingCycle.configuration, block.timestamp);

        // Package up a reconfiguration.
        JBFundingCycleConfig[] memory _firstReconfig = new JBFundingCycleConfig[](1);
        _firstReconfig[0].mustStartAtOrAfter = 0;
        _firstReconfig[0].data = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightFirstReconfiguration,
            discountRate: 0,
            ballot: _ballot
        }); // 3days ballot;
        _firstReconfig[0].metadata = _metadata;
        _firstReconfig[0].groupedSplits = _groupedSplits;
        _firstReconfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Submit a reconfiguration to-be overridden (will be in ApprovalExpected status due to ballot)
        vm.prank(multisig());
        _controller.reconfigureFundingCyclesOf(projectId, _firstReconfig, "");

        // Make sure the configuration is queued
        JBFundingCycle memory _queued = jbFundingCycleStore().queuedOf(projectId);
        assertEq(_queued.number, 2);
        assertEq(_queued.configuration, _initialTimestamp + 1);
        assertEq(_queued.weight, _weightFirstReconfiguration);

        // Package up another reconfiguration
        JBFundingCycleConfig[] memory _secondReconfig = new JBFundingCycleConfig[](1);
        _secondReconfig[0].mustStartAtOrAfter = block.timestamp + 9 days;
        _secondReconfig[0].data = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightSecondReconfiguration,
            discountRate: 0,
            ballot: _ballot
        }); // 3days ballot;
        _secondReconfig[0].metadata = _metadata;
        _secondReconfig[0].groupedSplits = _groupedSplits;
        _secondReconfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Submit the reconfiguration.
        // Will follow the rolledover (FC #1) cycle, after overriding the above config, bc first reconfig is in ApprovalExpected status (3 days ballot has not passed)
        // FC #1 rolls over bc our mustStartAtOrAfter occurs later than when FC #1 ends.
        vm.prank(multisig());
        _controller.reconfigureFundingCyclesOf(projectId, _secondReconfig, "");

        // Make sure this latest reconfiguration implies a rolled over cycle of FC #1.
        JBFundingCycle memory _requeued = jbFundingCycleStore().queuedOf(projectId);
        assertEq(_requeued.number, 2);
        assertEq(_requeued.configuration, _initialTimestamp);
        assertEq(_requeued.weight, _weightInitial);

        // Warp to when the initial configuration rolls over and again becomes the current
        vm.warp(block.timestamp + _CYCLE_DURATION * 1 days);

        // Make sure the new current is a rolled over configuration
        JBFundingCycle memory _initialIsCurrent = jbFundingCycleStore().currentOf(projectId);
        assertEq(_initialIsCurrent.number, 2);
        assertEq(_initialIsCurrent.configuration, _initialTimestamp);
        assertEq(_initialIsCurrent.weight, _weightInitial);

        // Queued second reconfiguration that replaced our first reconfiguration
        JBFundingCycle memory _requeued2 = jbFundingCycleStore().queuedOf(projectId);
        assertEq(_requeued2.number, 3);
        assertEq(_requeued2.configuration, _initialTimestamp + 2);
        assertEq(_requeued2.weight, _weightSecondReconfiguration);
    }

    function testSingleBlockOverwriteQueued() public {
        // Keep references to our different weights for assertions
        uint256 _weightFirstReconfiguration = 1234 * 10 ** 18;
        uint256 _weightSecondReconfiguration = 6969 * 10 ** 18;

        // Keep a reference to the expected timestamp after reconfigurations, starting now, incremented later in-line for readability.
        uint256 _expectedTimestamp = block.timestamp;

        // Package up a reconfiguration.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Deploy a project to test.
        uint256 projectId = launchProjectForTest();

        // Keep a reference to the current cycle.
        JBFundingCycle memory _fundingCycle = jbFundingCycleStore().currentOf(projectId);

        // Initial funding cycle data: will have a block.timestamp (configuration) that is 2 less than the second reconfiguration (timestamps are incremented when queued in same block now)
        assertEq(_fundingCycle.number, 1);
        assertEq(_fundingCycle.weight, _data.weight);

        // Package up another configuration.
        JBFundingCycleConfig[] memory _firstReconfig = new JBFundingCycleConfig[](1);
        _firstReconfig[0].mustStartAtOrAfter = block.timestamp + 3 days;
        _firstReconfig[0].data = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightFirstReconfiguration,
            discountRate: 0,
            ballot: _ballot
        }); // 3days ballot;
        _firstReconfig[0].metadata = _metadata;
        _firstReconfig[0].groupedSplits = _groupedSplits;
        _firstReconfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Becomes queued & will be overwritten as 3 days will not pass and it's status is "ApprovalExpected"
        vm.prank(multisig());
        _controller.reconfigureFundingCyclesOf(projectId, _firstReconfig, "");

        // Get a reference to the queued cycle.
        JBFundingCycle memory queuedToOverwrite = jbFundingCycleStore().queuedOf(projectId);

        assertEq(queuedToOverwrite.number, 2);
        assertEq(queuedToOverwrite.configuration, _expectedTimestamp + 1);
        assertEq(queuedToOverwrite.weight, _weightFirstReconfiguration);

        // Package up another reconfiguration to overwrite.
        JBFundingCycleConfig[] memory _secondReconfig = new JBFundingCycleConfig[](1);

        _secondReconfig[0].mustStartAtOrAfter = block.timestamp + _BALLOT_DURATION;
        _secondReconfig[0].data = JBFundingCycleData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightSecondReconfiguration,
            discountRate: 0,
            ballot: _ballot
        }); // 3days ballot;
        _secondReconfig[0].metadata = _metadata;
        _secondReconfig[0].groupedSplits = _groupedSplits;
        _secondReconfig[0].fundAccessConstraints = _fundAccessConstraints;

        // Overwriting reconfiguration
        vm.prank(multisig());
        _controller.reconfigureFundingCyclesOf(projectId, _secondReconfig, "");

        // Make sure it's overwritten.
        JBFundingCycle memory queued = jbFundingCycleStore().queuedOf(projectId);
        assertEq(queued.number, 2);
        assertEq(queued.configuration, _expectedTimestamp + 2);
        assertEq(queued.weight, _weightSecondReconfiguration);
    }

    function testBallot(uint256 _start, uint256 _configuration, uint256 _duration) public {
        _start = bound(_start, block.timestamp, block.timestamp + 1000 days);
        _configuration = bound(_configuration, block.timestamp, block.timestamp + 1000 days);
        _duration = bound(_duration, 1, block.timestamp);

        JBReconfigurationBufferBallot ballot = new JBReconfigurationBufferBallot(_duration);

        JBBallotState _currentState = ballot.stateOf(1, _configuration, _start); // 1 is the projectId, unused

        // Configuration is after ballot starting -> ballot failed
        if (_configuration > _start) {
            assertEq(uint256(_currentState), uint256(JBBallotState.Failed));
        }
        // ballot starts less than in less than a duration away from the configuration -> failed (ie would start mid-cycle)
        else if (_start - _duration < _configuration) {
            assertEq(uint256(_currentState), uint256(JBBallotState.Failed));
        }
        // ballot starts in more than a _duration away (ie will be approved when enough time has passed) -> approval expected
        else if (block.timestamp + _duration < _start) {
            assertEq(uint256(_currentState), uint256(JBBallotState.ApprovalExpected));
        }
        // if enough time has passed since ballot start, approved
        else if (block.timestamp + _duration > _start) {
            assertEq(uint256(_currentState), uint256(JBBallotState.Approved));
        }
    }
}
