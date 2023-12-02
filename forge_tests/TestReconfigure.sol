// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// A project's rulesets can be scheduled, and rescheduled so long as the provided approval hook approves.
contract TestReconfigureProject_Local is TestBaseWorkflow {
    IJBController private _controller;
    JBProjectMetadata private _projectMetadata;
    JBRulesetData private _data;
    JBRulesetData private _dataReconfiguration;
    JBRulesetMetadata private _metadata;
    JBDeadline private _deadline;
    JBSplitGroup[] private _splitGroup;
    JBFundAccessLimitGroup[] private _fundAccessLimitGroup;
    IJBTerminal private _terminal;

    uint256 private _BALLOT_DURATION = 3 days;
    uint256 private _CYCLE_DURATION = 6;

    function setUp() public override {
        super.setUp();

        _terminal = jbMultiTerminal();
        _controller = jbController();

        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        _deadline = new JBDeadline(_BALLOT_DURATION);
        _data = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 1000 * 10 ** 18,
            decayRate: 0,
            approvalHook: _deadline
        });
        _dataReconfiguration = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 69 * 10 ** 18,
            decayRate: 0,
            approvalHook: JBDeadline(address(0))
        });
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        _metadata = JBRulesetMetadata({
            global: JBGlobalRulesetMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: 0,
            baseCurrency: uint32(uint160(JBTokenList.Native)),
            pausePay: false,
            allowDiscretionaryMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalSurplusForRedemptions: false,
            useDataHookForPay: false,
            useDataHookForRedeem: false,
            dataHook: address(0),
            metadata: 0
        });
    }

    function launchProjectForTest() public returns (uint256) {
        // Package up cycle config.
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = new JBSplitGroup[](0);
        _rulesetConfig[0].fundAccessLimitGroup = new JBFundAccessLimitGroup[](0);

        // Package up terminal config.
        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
        _accountingContexts[0] = JBAccountingContextConfig({
            token: JBTokenList.Native,
            standard: JBTokenStandards.NATIVE
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        uint256 projectId = _controller.launchProjectFor({
            owner: address(multisig()),
            projectMetadata: _projectMetadata,
            rulesetConfigurations: _rulesetConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        return projectId;
    }

    function testReconfigureProject() public {
        // Package a funding cycle configuration.
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = _splitGroup;
        _rulesetConfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Deploy a project.
        uint256 projectId = launchProjectForTest();

        // Keep a reference to the current funding cycle.
        JBRuleset memory _fundingCycle = jbRulesets().currentOf(projectId);

        // Make sure the cycle has a number of 1.
        assertEq(_fundingCycle.cycleNumber, 1);
        // Make sure the cycle's weight matches.
        assertEq(_fundingCycle.weight, _data.weight);

        // Keep a reference to the cycle's configuration.
        uint256 _currentConfiguration = _fundingCycle.rulesetId;

        // Increment the weight to create a difference.
        _rulesetConfig[0].data.weight = _rulesetConfig[0].data.weight + 1;

        // Add a cycle.
        vm.prank(multisig());
        _controller.queueRulesetsOf(projectId, _rulesetConfig, "");

        // Make sure the current cycle hasn't changed.
        _fundingCycle = jbRulesets().currentOf(projectId);
        assertEq(_fundingCycle.cycleNumber, 1);
        assertEq(_fundingCycle.rulesetId, _currentConfiguration);
        assertEq(_fundingCycle.weight, _data.weight);

        // Go to the start of the next cycle.
        vm.warp(_fundingCycle.start + _fundingCycle.duration);

        // Get the current cycle.
        JBRuleset memory _newFundingCycle = jbRulesets().currentOf(projectId);
        // It should be the second cycle.
        assertEq(_newFundingCycle.cycleNumber, 2);
        assertEq(_newFundingCycle.weight, _data.weight + 1);
        assertEq(_newFundingCycle.basedOnId, _currentConfiguration);
    }

    function testMultipleReconfigurationOnRolledOver() public {
        // Keep references to two different weights.
        uint256 _weightFirstReconfiguration = 1234 * 10 ** 18;
        uint256 _weightSecondReconfiguration = 6969 * 10 ** 18;

        // Launch a project.
        uint256 projectId = launchProjectForTest();

        // Keep a reference to the current funding cycle.
        JBRuleset memory _fundingCycle = jbRulesets().currentOf(projectId);

        // Make sure the cycle is correct.
        assertEq(_fundingCycle.cycleNumber, 1);
        assertEq(_fundingCycle.weight, _data.weight);

        // Keep a reference to teh current configuration.
        uint256 _currentConfiguration = _fundingCycle.rulesetId;

        // Jump to the next funding cycle.
        vm.warp(block.timestamp + _fundingCycle.duration);

        // Package up a reconfiguration.
        JBRulesetConfig[] memory _firstReconfig = new JBRulesetConfig[](1);
        _firstReconfig[0].mustStartAtOrAfter = 0;
        _firstReconfig[0].data = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightFirstReconfiguration,
            decayRate: 0,
            approvalHook: _deadline
        }); // 3 day deadline duration.
        _firstReconfig[0].metadata = _metadata;
        _firstReconfig[0].splitGroups = _splitGroup;
        _firstReconfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Reconfigure
        vm.prank(multisig());
        _controller.queueRulesetsOf(projectId, _firstReconfig, "");

        // Package up another reconfiguration.
        JBRulesetConfig[] memory _secondReconfig = new JBRulesetConfig[](1);
        _secondReconfig[0].mustStartAtOrAfter = 0;
        _secondReconfig[0].data = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightSecondReconfiguration,
            decayRate: 0,
            approvalHook: _deadline
        }); // 3 day deadline duration.
        _secondReconfig[0].metadata = _metadata;
        _secondReconfig[0].splitGroups = _splitGroup;
        _secondReconfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Reconfigure again
        vm.prank(multisig());
        _controller.queueRulesetsOf(projectId, _secondReconfig, "");

        // Since the second reconfiguration happened during the same block as the one prior, increment the config.
        uint256 secondReconfiguration = block.timestamp + 1;

        // The current funding cycle should not have changed, still in FC#2, rolled over from FC#1.
        _fundingCycle = jbRulesets().currentOf(projectId);
        assertEq(_fundingCycle.cycleNumber, 2);
        assertEq(_fundingCycle.rulesetId, _currentConfiguration);
        assertEq(_fundingCycle.weight, _data.weight);

        // Jump to after the deadline passed, but before the next FC
        vm.warp(_fundingCycle.start + _fundingCycle.duration - 1);

        // Make sure the queued fuding cycle is the second reconfiguration
        JBRuleset memory queuedFundingCycle = jbRulesets().upcomingRulesetOf(projectId);
        assertEq(queuedFundingCycle.cycleNumber, 3);
        assertEq(queuedFundingCycle.rulesetId, secondReconfiguration);
        assertEq(queuedFundingCycle.weight, _weightSecondReconfiguration);

        // Go the the start of the queued cycle.
        vm.warp(_fundingCycle.start + _fundingCycle.duration);

        // Make sure the second reconfiguration is now the current one
        JBRuleset memory _newFundingCycle = jbRulesets().currentOf(projectId);
        assertEq(_newFundingCycle.cycleNumber, 3);
        assertEq(_newFundingCycle.rulesetId, secondReconfiguration);
        assertEq(_newFundingCycle.weight, _weightSecondReconfiguration);
    }

    function testMultipleReconfigure(uint8 _deadlineDuration) public {
        // Create a deadline with the provided approval duration threshold.
        _deadline = new JBDeadline(_deadlineDuration);

        // Package the funding cycle configuration data.
        _data = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 10_000 ether,
            decayRate: 0,
            approvalHook: _deadline
        });
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = _splitGroup;
        _rulesetConfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Launch a project to test.
        uint256 projectId = launchProjectForTest();

        // Keep a reference to the initial, current, and queued cycles.
        JBRuleset memory initialFundingCycle = jbRulesets().currentOf(projectId);
        JBRuleset memory currentFundingCycle = initialFundingCycle;
        JBRuleset memory queuedFundingCycle = jbRulesets().upcomingRulesetOf(projectId);

        for (uint256 i = 0; i < _CYCLE_DURATION + 1; i++) {
            // If the deadline is less than the cycle's duration, make sure the current cycle's weight is linearly decremented.
            if (_deadlineDuration + i * 1 days < currentFundingCycle.duration) {
                assertEq(currentFundingCycle.weight, initialFundingCycle.weight - i);
            }

            // Package up a new funding cycle with decremented weight.
            _data = JBRulesetData({
                duration: _CYCLE_DURATION * 1 days,
                weight: initialFundingCycle.weight - (i + 1), // i+1 -> next funding cycle
                decayRate: 0,
                approvalHook: _deadline
            });
            JBRulesetConfig[] memory _reconfig = new JBRulesetConfig[](1);
            _reconfig[0].mustStartAtOrAfter = 0;
            _reconfig[0].data = _data;
            _reconfig[0].metadata = _metadata;
            _reconfig[0].splitGroups = _splitGroup;
            _reconfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

            // Submit the reconfiguration.
            vm.prank(multisig());
            _controller.queueRulesetsOf(projectId, _reconfig, "");

            // Get a refernce to the current and queued funding cycles.
            currentFundingCycle = jbRulesets().currentOf(projectId);
            queuedFundingCycle = jbRulesets().upcomingRulesetOf(projectId);

            // Make sure the queued cycle is the funding cycle currently under the deadline duration.
            assertEq(queuedFundingCycle.weight, _data.weight);

            // If the full deadline duration included in the funding cycle.
            if (
                _deadlineDuration == 0
                    || currentFundingCycle.duration % (_deadlineDuration + i * 1 days)
                        < currentFundingCycle.duration
            ) {
                // Make sure the current cycle's weight is still linearly decremented.
                assertEq(currentFundingCycle.weight, initialFundingCycle.weight - i);

                // Shift forward the start of the deadline into the fc, one day at a time, from fc to fc
                vm.warp(currentFundingCycle.start + currentFundingCycle.duration + i * 1 days);

                // Make sure what was the queued cycle is now current.
                currentFundingCycle = jbRulesets().currentOf(projectId);
                assertEq(currentFundingCycle.weight, _data.weight);

                // Make sure queued is the rolled-over version of current.
                queuedFundingCycle = jbRulesets().upcomingRulesetOf(projectId);
                assertEq(queuedFundingCycle.weight, _data.weight);
            }
            // If the deadline duration is accross many funding cycles.
            else {
                // Make sure the current funding cycle has rolled over.
                vm.warp(currentFundingCycle.start + currentFundingCycle.duration);
                assertEq(currentFundingCycle.weight, initialFundingCycle.weight - i);

                // Make sure the new funding cycle has started once the deadline duration has passed.
                vm.warp(
                    currentFundingCycle.start + currentFundingCycle.duration + _deadlineDuration
                );
                currentFundingCycle = jbRulesets().currentOf(projectId);
                assertEq(currentFundingCycle.weight, _data.weight);
            }
        }
    }

    function testLaunchProjectWrongBallot() public {
        /// Pacakge the configuration.
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = _splitGroup;
        _rulesetConfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Launch the project.
        uint256 projectId = launchProjectForTest();

        // Package another with a bad approval hook.
        JBRulesetData memory _dataNew = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 12_345 * 10 ** 18,
            decayRate: 0,
            approvalHook: IJBRulesetApprovalHook(address(6969)) // Wrong approval hook address
        });

        vm.prank(multisig());
        vm.expectRevert(abi.encodeWithSignature("INVALID_RULESET_APPROVAL_HOOK()"));

        JBRulesetConfig[] memory _reconfig = new JBRulesetConfig[](1);
        _reconfig[0].mustStartAtOrAfter = 0;
        _reconfig[0].data = _dataNew;
        _reconfig[0].metadata = _metadata;
        _reconfig[0].splitGroups = _splitGroup;
        _reconfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        _controller.queueRulesetsOf(projectId, _reconfig, "");
    }

    function testReconfigureShortDurationProject() public {
        uint256 _shortDuration = 5 minutes;

        // Package a funding cycle reconfiguration.
        _data = JBRulesetData({
            duration: _shortDuration,
            weight: 10_000 * 10 ** 18,
            decayRate: 0,
            approvalHook: _deadline
        });
        _dataReconfiguration = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 69 * 10 ** 18,
            decayRate: 0,
            approvalHook: IJBRulesetApprovalHook(address(0))
        });
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = _splitGroup;
        _rulesetConfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Launch a project to test.
        uint256 projectId = launchProjectForTest();

        // Get a reference to the current funding cycle.
        JBRuleset memory _fundingCycle = jbRulesets().currentOf(projectId);

        // Make sure the current funding cycle is correct.
        assertEq(_fundingCycle.cycleNumber, 1); // ok
        assertEq(_fundingCycle.weight, _data.weight);

        // Keep a reference to the current configuration.
        uint256 _currentConfiguration = _fundingCycle.rulesetId;

        // Package up a reconfiguration.
        JBRulesetConfig[] memory _reconfig = new JBRulesetConfig[](1);
        _reconfig[0].mustStartAtOrAfter = 0;
        _reconfig[0].data = _dataReconfiguration;
        _reconfig[0].metadata = _metadata;
        _reconfig[0].splitGroups = _splitGroup;
        _reconfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Submit the reconfiguration.
        vm.prank(multisig());
        _controller.queueRulesetsOf(projectId, _reconfig, "");

        // Make sure the cycle hasn't changed.
        _fundingCycle = jbRulesets().currentOf(projectId);
        assertEq(_fundingCycle.cycleNumber, 1);
        assertEq(_fundingCycle.rulesetId, _currentConfiguration);
        assertEq(_fundingCycle.weight, _data.weight);

        // Go the the second cycle.
        vm.warp(_fundingCycle.start + _fundingCycle.duration);

        // Make sure the cycle rolled over.
        JBRuleset memory _newFundingCycle = jbRulesets().currentOf(projectId);
        assertEq(_newFundingCycle.cycleNumber, 2);
        assertEq(_newFundingCycle.weight, _data.weight);

        // Go to the end of the deadline duration.
        vm.warp(_fundingCycle.start + _fundingCycle.duration + _BALLOT_DURATION);

        // Make sure the reconfiguration is in effect.
        _newFundingCycle = jbRulesets().currentOf(projectId);
        assertEq(
            _newFundingCycle.cycleNumber,
            _fundingCycle.cycleNumber + (_BALLOT_DURATION / _shortDuration) + 1
        );
        assertEq(_newFundingCycle.weight, _dataReconfiguration.weight);
    }

    function testReconfigureWithoutBallot() public {
        // Package a reconfiguration.
        _data = JBRulesetData({
            duration: 5 minutes,
            weight: 10_000 * 10 ** 18,
            decayRate: 0,
            approvalHook: IJBRulesetApprovalHook(address(0))
        });
        _dataReconfiguration = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: 69 * 10 ** 18,
            decayRate: 0,
            approvalHook: IJBRulesetApprovalHook(address(0))
        });
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = _splitGroup;
        _rulesetConfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Launch a project to test with.
        uint256 projectId = launchProjectForTest();

        // Get a reference to the current funding cycle.
        JBRuleset memory _fundingCycle = jbRulesets().currentOf(projectId);

        // Make sure the cycle is expected.
        assertEq(_fundingCycle.cycleNumber, 1);
        assertEq(_fundingCycle.weight, _data.weight);

        // Package a reconfiguration.
        JBRulesetConfig[] memory _reconfig = new JBRulesetConfig[](1);

        _reconfig[0].mustStartAtOrAfter = 0;
        _reconfig[0].data = _dataReconfiguration;
        _reconfig[0].metadata = _metadata;
        _reconfig[0].splitGroups = _splitGroup;
        _reconfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        vm.prank(multisig());
        _controller.queueRulesetsOf(projectId, _reconfig, "");

        // Make sure the cycle hasn't changed.
        _fundingCycle = jbRulesets().currentOf(projectId);
        assertEq(_fundingCycle.cycleNumber, 1);
        assertEq(_fundingCycle.weight, _data.weight);

        // Make sure the cycle has changed once the cycle is over.
        vm.warp(_fundingCycle.start + _fundingCycle.duration);
        _fundingCycle = jbRulesets().currentOf(projectId);
        assertEq(_fundingCycle.cycleNumber, 2);
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
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightInitial,
            decayRate: 0,
            approvalHook: _deadline
        }); // 3 day deadline duration.
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = _splitGroup;
        _rulesetConfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Launch the project to test with.
        uint256 projectId = launchProjectForTest();

        // Send the reconfiguration.
        JBRuleset memory _fundingCycle = jbRulesets().currentOf(projectId);

        // Make sure the first cycle has begun.
        assertEq(_fundingCycle.cycleNumber, 1);
        assertEq(_fundingCycle.weight, _weightInitial);
        assertEq(_fundingCycle.rulesetId, block.timestamp);

        // Package up a reconfiguration.
        JBRulesetConfig[] memory _firstReconfig = new JBRulesetConfig[](1);
        _firstReconfig[0].mustStartAtOrAfter = 0;
        _firstReconfig[0].data = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightFirstReconfiguration,
            decayRate: 0,
            approvalHook: _deadline
        }); // 3 day deadline duration.
        _firstReconfig[0].metadata = _metadata;
        _firstReconfig[0].splitGroups = _splitGroup;
        _firstReconfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Submit a reconfiguration to-be overridden (will be in ApprovalExpected status due to approval hook)
        vm.prank(multisig());
        _controller.queueRulesetsOf(projectId, _firstReconfig, "");

        // Make sure the configuration is queued
        JBRuleset memory _queued = jbRulesets().upcomingRulesetOf(projectId);
        assertEq(_queued.cycleNumber, 2);
        assertEq(_queued.rulesetId, _initialTimestamp + 1);
        assertEq(_queued.weight, _weightFirstReconfiguration);

        // Package up another reconfiguration
        JBRulesetConfig[] memory _secondReconfig = new JBRulesetConfig[](1);
        _secondReconfig[0].mustStartAtOrAfter = block.timestamp + 9 days;
        _secondReconfig[0].data = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightSecondReconfiguration,
            decayRate: 0,
            approvalHook: _deadline
        }); // 3 day deadline duration.
        _secondReconfig[0].metadata = _metadata;
        _secondReconfig[0].splitGroups = _splitGroup;
        _secondReconfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Submit the reconfiguration.
        // Will follow the rolledover (FC #1) cycle, after overriding the above config, bc first reconfig is in ApprovalExpected status (3 days deadline has not passed)
        // FC #1 rolls over bc our mustStartAtOrAfter occurs later than when FC #1 ends.
        vm.prank(multisig());
        _controller.queueRulesetsOf(projectId, _secondReconfig, "");

        // Make sure this latest reconfiguration implies a rolled over cycle of FC #1.
        JBRuleset memory _requeued = jbRulesets().upcomingRulesetOf(projectId);
        assertEq(_requeued.cycleNumber, 2);
        assertEq(_requeued.rulesetId, _initialTimestamp);
        assertEq(_requeued.weight, _weightInitial);

        // Warp to when the initial configuration rolls over and again becomes the current
        vm.warp(block.timestamp + _CYCLE_DURATION * 1 days);

        // Make sure the new current is a rolled over configuration
        JBRuleset memory _initialIsCurrent = jbRulesets().currentOf(projectId);
        assertEq(_initialIsCurrent.cycleNumber, 2);
        assertEq(_initialIsCurrent.rulesetId, _initialTimestamp);
        assertEq(_initialIsCurrent.weight, _weightInitial);

        // Queued second reconfiguration that replaced our first reconfiguration
        JBRuleset memory _requeued2 = jbRulesets().upcomingRulesetOf(projectId);
        assertEq(_requeued2.cycleNumber, 3);
        assertEq(_requeued2.rulesetId, _initialTimestamp + 2);
        assertEq(_requeued2.weight, _weightSecondReconfiguration);
    }

    function testSingleBlockOverwriteQueued() public {
        // Keep references to our different weights for assertions
        uint256 _weightFirstReconfiguration = 1234 * 10 ** 18;
        uint256 _weightSecondReconfiguration = 6969 * 10 ** 18;

        // Keep a reference to the expected timestamp after reconfigurations, starting now, incremented later in-line for readability.
        uint256 _expectedTimestamp = block.timestamp;

        // Package up a reconfiguration.
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = _splitGroup;
        _rulesetConfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Deploy a project to test.
        uint256 projectId = launchProjectForTest();

        // Keep a reference to the current cycle.
        JBRuleset memory _fundingCycle = jbRulesets().currentOf(projectId);

        // Initial funding cycle data: will have a block.timestamp (configuration) that is 2 less than the second reconfiguration (timestamps are incremented when queued in same block now)
        assertEq(_fundingCycle.cycleNumber, 1);
        assertEq(_fundingCycle.weight, _data.weight);

        // Package up another configuration.
        JBRulesetConfig[] memory _firstReconfig = new JBRulesetConfig[](1);
        _firstReconfig[0].mustStartAtOrAfter = block.timestamp + 3 days;
        _firstReconfig[0].data = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightFirstReconfiguration,
            decayRate: 0,
            approvalHook: _deadline
        }); // 3 day deadline duration.
        _firstReconfig[0].metadata = _metadata;
        _firstReconfig[0].splitGroups = _splitGroup;
        _firstReconfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Becomes queued & will be overwritten as 3 days will not pass and it's status is "ApprovalExpected"
        vm.prank(multisig());
        _controller.queueRulesetsOf(projectId, _firstReconfig, "");

        // Get a reference to the queued cycle.
        JBRuleset memory queuedToOverwrite = jbRulesets().upcomingRulesetOf(projectId);

        assertEq(queuedToOverwrite.cycleNumber, 2);
        assertEq(queuedToOverwrite.rulesetId, _expectedTimestamp + 1);
        assertEq(queuedToOverwrite.weight, _weightFirstReconfiguration);

        // Package up another reconfiguration to overwrite.
        JBRulesetConfig[] memory _secondReconfig = new JBRulesetConfig[](1);

        _secondReconfig[0].mustStartAtOrAfter = block.timestamp + _BALLOT_DURATION;
        _secondReconfig[0].data = JBRulesetData({
            duration: _CYCLE_DURATION * 1 days,
            weight: _weightSecondReconfiguration,
            decayRate: 0,
            approvalHook: _deadline
        }); // 3 day deadline duration.
        _secondReconfig[0].metadata = _metadata;
        _secondReconfig[0].splitGroups = _splitGroup;
        _secondReconfig[0].fundAccessLimitGroup = _fundAccessLimitGroup;

        // Overwriting reconfiguration
        vm.prank(multisig());
        _controller.queueRulesetsOf(projectId, _secondReconfig, "");

        // Make sure it's overwritten.
        JBRuleset memory queued = jbRulesets().upcomingRulesetOf(projectId);
        assertEq(queued.cycleNumber, 2);
        assertEq(queued.rulesetId, _expectedTimestamp + 2);
        assertEq(queued.weight, _weightSecondReconfiguration);
    }

    function testBallot(uint256 _start, uint256 _configuration, uint256 _duration) public {
        _start = bound(_start, block.timestamp, block.timestamp + 1000 days);
        _configuration = bound(_configuration, block.timestamp, block.timestamp + 1000 days);
        _duration = bound(_duration, 1, block.timestamp);

        JBDeadline deadline = new JBDeadline(_duration);

        JBApprovalStatus _currentStatus = deadline.approvalStatusOf(1, _configuration, _start); // 1 is the projectId, unused

        // Configuration is after deadline -> approval hook failed
        if (_configuration > _start) {
            assertEq(uint256(_currentStatus), uint256(JBApprovalStatus.Failed));
        }
        // deadline starts less than in less than a duration away from the configuration -> failed (ie would start mid-cycle)
        else if (_start - _duration < _configuration) {
            assertEq(uint256(_currentStatus), uint256(JBApprovalStatus.Failed));
        }
        // deadline starts in more than a _duration away (ie will be approved when enough time has passed) -> approval expected
        else if (block.timestamp + _duration < _start) {
            assertEq(uint256(_currentStatus), uint256(JBApprovalStatus.ApprovalExpected));
        }
        // If enough time has passed since deadline start, approved.
        else if (block.timestamp + _duration > _start) {
            assertEq(uint256(_currentStatus), uint256(JBApprovalStatus.Approved));
        }
    }
}
