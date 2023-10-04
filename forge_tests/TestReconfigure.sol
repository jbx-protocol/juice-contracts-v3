// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

uint256 constant WEIGHT = 1000 * 10 ** 18;

contract TestReconfigureProject_Local is TestBaseWorkflow {
    JBController controller;
    JBProjectMetadata _projectMetadata;
    JBFundingCycleData _data;
    JBFundingCycleData _dataReconfiguration;
    JBFundingCycleData _dataWithoutBallot;
    JBFundingCycleMetadata _metadata;
    JBReconfigurationBufferBallot _ballot;
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
    IJBPaymentTerminal[] _terminals; // Default empty

    uint256 BALLOT_DURATION = 3 days;

    function setUp() public override {
        super.setUp();

        controller = jbController();

        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        _ballot = new JBReconfigurationBufferBallot(BALLOT_DURATION);

        _data = JBFundingCycleData({duration: 6 days, weight: 10000 * 10 ** 18, discountRate: 0, ballot: _ballot});

        _dataWithoutBallot = JBFundingCycleData({
            duration: 6 days,
            weight: 1000 * 10 ** 18,
            discountRate: 0,
            ballot: JBReconfigurationBufferBallot(address(0))
        });

        _dataReconfiguration = JBFundingCycleData({
            duration: 6 days,
            weight: 69 * 10 ** 18,
            discountRate: 0,
            ballot: JBReconfigurationBufferBallot(address(0))
        });

        _metadata = JBFundingCycleMetadata({
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

        _terminals = [jbETHPaymentTerminal()];
    }

    function testReconfigureProject() public {
        uint256 projectId = controller.launchProjectFor(
            multisig(),
            _projectMetadata,
            _data,
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        JBFundingCycle memory fundingCycle = jbFundingCycleStore().currentOf(projectId);

        assertEq(fundingCycle.number, 1); // ok
        assertEq(fundingCycle.weight, _data.weight);

        uint256 currentConfiguration = fundingCycle.configuration;

        vm.warp(block.timestamp + 1); // Avoid overwriting if same timestamp

        vm.prank(multisig());
        controller.reconfigureFundingCyclesOf(
            projectId,
            _data, // 3days ballot
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );

        // Shouldn't have changed
        fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(fundingCycle.number, 1);
        assertEq(fundingCycle.configuration, currentConfiguration);
        assertEq(fundingCycle.weight, _data.weight);

        // should be new funding cycle
        vm.warp(fundingCycle.start + fundingCycle.duration);

        JBFundingCycle memory newFundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(newFundingCycle.number, 2);
        assertEq(newFundingCycle.weight, _data.weight);
    }

    function testMultipleReconfigurationOnRolledOver() public {
        uint256 weightFirstReconfiguration = 1234 * 10 ** 18;
        uint256 weightSecondReconfiguration = 6969 * 10 ** 18;

        uint256 projectId = controller.launchProjectFor(
            multisig(),
            _projectMetadata,
            _data,
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        JBFundingCycle memory fundingCycle = jbFundingCycleStore().currentOf(projectId);

        // Initial funding cycle data
        assertEq(fundingCycle.number, 1);
        assertEq(fundingCycle.weight, _data.weight);

        uint256 currentConfiguration = fundingCycle.configuration;

        // Jump to FC+1, rolled over
        vm.warp(block.timestamp + fundingCycle.duration);

        // First reconfiguration
        vm.prank(multisig());
        controller.reconfigureFundingCyclesOf(
            projectId,
            JBFundingCycleData({duration: 6 days, weight: weightFirstReconfiguration, discountRate: 0, ballot: _ballot}), // 3days ballot
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );

        vm.warp(block.timestamp + 1); // Avoid overwrite

        // Second reconfiguration (different configuration)
        vm.prank(multisig());
        controller.reconfigureFundingCyclesOf(
            projectId,
            JBFundingCycleData({duration: 6 days, weight: weightSecondReconfiguration, discountRate: 0, ballot: _ballot}), // 3days ballot
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );
        uint256 secondReconfiguration = block.timestamp;

        // Shouldn't have changed, still in FC#2, rolled over from FC#1
        fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(fundingCycle.number, 2);
        assertEq(fundingCycle.configuration, currentConfiguration);
        assertEq(fundingCycle.weight, _data.weight);

        // Jump to after the ballot passed, but before the next FC
        vm.warp(fundingCycle.start + fundingCycle.duration - 1);

        // Queued should be the second reconfiguration
        JBFundingCycle memory queuedFundingCycle = jbFundingCycleStore().queuedOf(projectId);
        assertEq(queuedFundingCycle.number, 3);
        assertEq(queuedFundingCycle.configuration, secondReconfiguration);
        assertEq(queuedFundingCycle.weight, weightSecondReconfiguration);

        vm.warp(fundingCycle.start + fundingCycle.duration);

        // Second reconfiguration should be now the current one
        JBFundingCycle memory newFundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(newFundingCycle.number, 3);
        assertEq(newFundingCycle.configuration, secondReconfiguration);
        assertEq(newFundingCycle.weight, weightSecondReconfiguration);
    }

    function testMultipleReconfigure(uint8 FUZZED_BALLOT_DURATION) public {
        _ballot = new JBReconfigurationBufferBallot(FUZZED_BALLOT_DURATION);

        _data = JBFundingCycleData({duration: 6 days, weight: 10000 ether, discountRate: 0, ballot: _ballot});

        uint256 projectId = controller.launchProjectFor(
            multisig(),
            _projectMetadata,
            _data, // duration 6 days, weight=10k, ballot 3days
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        JBFundingCycle memory initialFundingCycle = jbFundingCycleStore().currentOf(projectId);
        JBFundingCycle memory currentFundingCycle = initialFundingCycle;
        JBFundingCycle memory queuedFundingCycle = jbFundingCycleStore().queuedOf(projectId);

        vm.warp(currentFundingCycle.start + 1); // Avoid overwriting current fc while reconfiguring

        for (uint256 i = 0; i < 4; i++) {
            currentFundingCycle = jbFundingCycleStore().currentOf(projectId);

            if (FUZZED_BALLOT_DURATION + i * 1 days < currentFundingCycle.duration) {
                assertEq(currentFundingCycle.weight, initialFundingCycle.weight - i);
            }

            _data = JBFundingCycleData({
                duration: 6 days,
                weight: initialFundingCycle.weight - (i + 1), // i+1 -> next funding cycle
                discountRate: 0,
                ballot: _ballot
            });

            vm.prank(multisig());
            controller.reconfigureFundingCyclesOf(
                projectId, _data, _metadata, 0, _groupedSplits, _fundAccessConstraints, ""
            );

            currentFundingCycle = jbFundingCycleStore().currentOf(projectId);
            queuedFundingCycle = jbFundingCycleStore().queuedOf(projectId);

            // Queued is the funding cycle currently under ballot
            assertEq(queuedFundingCycle.weight, _data.weight);
            assertEq(queuedFundingCycle.number, currentFundingCycle.number + 1);

            // Is the full ballot duration included in the funding cycle?
            if (
                FUZZED_BALLOT_DURATION == 0
                    || currentFundingCycle.duration % (FUZZED_BALLOT_DURATION + i * 1 days) < currentFundingCycle.duration
            ) {
                assertEq(currentFundingCycle.weight, initialFundingCycle.weight - i);

                uint256 _previousFundingCycleNumber = currentFundingCycle.number;

                // we shift forward the start of the ballot into the fc, one day at a time, from fc to fc
                vm.warp(currentFundingCycle.start + currentFundingCycle.duration + i * 1 days);

                // Ballot was Approved and we've changed fc, current is the reconfiguration
                currentFundingCycle = jbFundingCycleStore().currentOf(projectId);
                assertEq(currentFundingCycle.weight, _data.weight);
                assertEq(currentFundingCycle.number, _previousFundingCycleNumber + 1);

                // Queued is the reconfiguration rolled-over
                queuedFundingCycle = jbFundingCycleStore().queuedOf(projectId);
                assertEq(queuedFundingCycle.weight, _data.weight);
                assertEq(queuedFundingCycle.number, currentFundingCycle.number + 1);
            }
            // the ballot is accross two funding cycles
            else {
                // Warp to begining of next FC: should be the previous fc config rolled over (ballot is in Failed state)
                vm.warp(currentFundingCycle.start + currentFundingCycle.duration);
                assertEq(currentFundingCycle.weight, initialFundingCycle.weight - i);
                uint256 cycleNumber = currentFundingCycle.number;

                // Warp to after the end of the ballot, within the same fc: should be the new fc (ballot is in Approved state)
                vm.warp(currentFundingCycle.start + currentFundingCycle.duration + FUZZED_BALLOT_DURATION);
                currentFundingCycle = jbFundingCycleStore().currentOf(projectId);
                assertEq(currentFundingCycle.weight, _data.weight);
                assertEq(currentFundingCycle.number, cycleNumber + 1);
            }
        }
    }

    function testReconfigureProjectFuzzRates(uint96 RESERVED_RATE, uint96 REDEMPTION_RATE, uint256 BALANCE) public {
        BALANCE = bound(BALANCE, 100, payable(msg.sender).balance / 2);

        address _beneficiary = address(69420);
        uint256 projectId = controller.launchProjectFor(
            multisig(),
            _projectMetadata,
            _dataWithoutBallot,
            _metadata,
            0, // _mustStartAtOrAfter
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        JBFundingCycle memory fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(fundingCycle.number, 1);

        vm.warp(block.timestamp + 1);

        jbETHPaymentTerminal().pay{value: BALANCE}(
            projectId, BALANCE, address(0), _beneficiary, 0, false, "Forge test", new bytes(0)
        );

        uint256 _userTokenBalance = PRBMath.mulDiv(BALANCE, (WEIGHT / 10 ** 18), 2); // initial FC rate is 50%
        if (BALANCE != 0) {
            assertEq(jbTokenStore().balanceOf(_beneficiary, projectId), _userTokenBalance);
        }

        vm.prank(multisig());
        if (RESERVED_RATE > 10000) {
            vm.expectRevert(abi.encodeWithSignature("INVALID_RESERVED_RATE()"));
        } else if (REDEMPTION_RATE > 10000) {
            vm.expectRevert(abi.encodeWithSignature("INVALID_REDEMPTION_RATE()"));
        }

        controller.reconfigureFundingCyclesOf(
            projectId,
            _dataWithoutBallot,
            JBFundingCycleMetadata({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false,
                    pauseTransfers: false
                }),
                reservedRate: RESERVED_RATE,
                redemptionRate: REDEMPTION_RATE,
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
            }),
            0,
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );

        if (RESERVED_RATE > 10000 || REDEMPTION_RATE > 10000) {
            REDEMPTION_RATE = 5000; // If reconfigure has reverted, keep previous rates
            RESERVED_RATE = 5000;
        }

        vm.warp(block.timestamp + fundingCycle.duration);

        fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(fundingCycle.number, 2);

        jbETHPaymentTerminal().pay{value: BALANCE}(
            projectId, BALANCE, address(0), _beneficiary, 0, false, "Forge test", new bytes(0)
        );

        uint256 _newUserTokenBalance = RESERVED_RATE == 0 // New fc, rate is RESERVED_RATE
            ? PRBMath.mulDiv(BALANCE, WEIGHT, 10 ** 18)
            : PRBMath.mulDiv(PRBMath.mulDiv(BALANCE, WEIGHT, 10 ** 18), 10000 - RESERVED_RATE, 10000);

        if (BALANCE != 0) {
            assertEq(jbTokenStore().balanceOf(_beneficiary, projectId), _userTokenBalance + _newUserTokenBalance);
        }

        uint256 tokenBalance = jbTokenStore().balanceOf(_beneficiary, projectId);

        uint256 totalSupply;
        if (isUsingJbController3_0()) {
            totalSupply = jbController().totalOutstandingTokensOf(projectId, RESERVED_RATE);
        } else {
            totalSupply = IJBController3_1(address(jbController())).totalOutstandingTokensOf(projectId);
        }

        uint256 overflow = jbETHPaymentTerminal().currentEthOverflowOf(projectId);

        vm.startPrank(_beneficiary);
        jbETHPaymentTerminal().redeemTokensOf(
            _beneficiary,
            projectId,
            tokenBalance,
            address(0), //token (unused)
            0,
            payable(_beneficiary),
            "",
            new bytes(0)
        );
        vm.stopPrank();

        if (BALANCE != 0 && REDEMPTION_RATE != 0) {
            assertEq(
                _beneficiary.balance,
                PRBMath.mulDiv(
                    PRBMath.mulDiv(overflow, tokenBalance, totalSupply),
                    REDEMPTION_RATE + PRBMath.mulDiv(tokenBalance, 10000 - REDEMPTION_RATE, totalSupply),
                    10000
                )
            );
        }
    }

    function testLaunchProjectWrongBallot() public {
        uint256 projectId = controller.launchProjectFor(
            multisig(),
            _projectMetadata,
            _data,
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        JBFundingCycleData memory _dataNew = JBFundingCycleData({
            duration: 6 days,
            weight: 12345 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(6969)) // Wrong ballot address
        });

        vm.warp(block.timestamp + 1); // Avoid overwriting if same timestamp

        vm.prank(multisig());
        vm.expectRevert(abi.encodeWithSignature("INVALID_BALLOT()"));
        controller.reconfigureFundingCyclesOf(
            projectId,
            _dataNew, // wrong ballot
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );
    }

    function testReconfigureShortDurationProject() public {
        _data = JBFundingCycleData({duration: 5 minutes, weight: 10000 * 10 ** 18, discountRate: 0, ballot: _ballot});

        _dataReconfiguration = JBFundingCycleData({
            duration: 6 days,
            weight: 69 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        uint256 projectId = controller.launchProjectFor(
            multisig(),
            _projectMetadata,
            _data,
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        JBFundingCycle memory fundingCycle = jbFundingCycleStore().currentOf(projectId);

        assertEq(fundingCycle.number, 1); // ok
        assertEq(fundingCycle.weight, _data.weight);

        uint256 currentConfiguration = fundingCycle.configuration;

        vm.warp(block.timestamp + 1); // Avoid overwriting if same timestamp

        vm.prank(multisig());
        controller.reconfigureFundingCyclesOf(
            projectId,
            _dataReconfiguration,
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );

        // Shouldn't have changed (same cycle, with a ballot)
        fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(fundingCycle.number, 1);
        assertEq(fundingCycle.configuration, currentConfiguration);
        assertEq(fundingCycle.weight, _data.weight);

        // shouldn't have changed (new cycle but ballot is still active)
        vm.warp(fundingCycle.start + fundingCycle.duration);

        JBFundingCycle memory newFundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(newFundingCycle.number, 2);
        assertEq(newFundingCycle.weight, _data.weight);

        // should now be the reconfiguration (ballot duration is over)
        vm.warp(fundingCycle.start + fundingCycle.duration + 3 days);

        newFundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(newFundingCycle.number, fundingCycle.number + (3 days / 5 minutes) + 1);
        assertEq(newFundingCycle.weight, _dataReconfiguration.weight);
    }

    function testReconfigureWithoutBallot() public {
        _data = JBFundingCycleData({
            duration: 5 minutes,
            weight: 10000 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _dataReconfiguration = JBFundingCycleData({
            duration: 6 days,
            weight: 69 * 10 ** 18,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        uint256 projectId = controller.launchProjectFor(
            multisig(),
            _projectMetadata,
            _data,
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        JBFundingCycle memory fundingCycle = jbFundingCycleStore().currentOf(projectId);

        assertEq(fundingCycle.number, 1);
        assertEq(fundingCycle.weight, _data.weight);

        vm.warp(block.timestamp + 10); // Avoid overwriting if same timestamp

        vm.prank(multisig());
        controller.reconfigureFundingCyclesOf(
            projectId,
            _dataReconfiguration,
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );
        // Should not have changed
        fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(fundingCycle.number, 1);
        assertEq(fundingCycle.weight, _data.weight);

        // Should have changed after the current funding cycle is over
        vm.warp(fundingCycle.start + fundingCycle.duration);
        fundingCycle = jbFundingCycleStore().currentOf(projectId);
        assertEq(fundingCycle.number, 2);
        assertEq(fundingCycle.weight, _dataReconfiguration.weight);
    }

    function testMixedStarts() public {
        // Keep references to our different weights for assertions
        uint256 weightInitial = 1000 * 10 ** 18;
        uint256 weightFirstReconfiguration = 1234 * 10 ** 18;
        uint256 weightSecondReconfiguration = 6969 * 10 ** 18;

        // Keep a reference to the expected configuration timestamps
        uint256 initialTimestamp = block.timestamp;
        uint256 expectedTimestamp = block.timestamp;

        uint256 projectId = controller.launchProjectFor(
            multisig(),
            _projectMetadata,
            JBFundingCycleData({duration: 6 days, weight: weightInitial, discountRate: 0, ballot: JBReconfigurationBufferBallot(_ballot)}), // 3days ballot
            _metadata,
            0,
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        JBFundingCycle memory fundingCycle = jbFundingCycleStore().currentOf(projectId);

        // First cycle has begun
        assertEq(fundingCycle.number, 1);
        assertEq(fundingCycle.weight, weightInitial);
        assertEq(fundingCycle.configuration, block.timestamp);

        // create a to-be overridden reconfiguration (will be in ApprovalExpected status due to ballot)
        vm.prank(multisig());
        controller.reconfigureFundingCyclesOf(
            projectId,
            JBFundingCycleData({duration: 6 days, weight: weightFirstReconfiguration, discountRate: 0, ballot: JBReconfigurationBufferBallot(_ballot)}), // 3days ballot
            _metadata,
            0, // Start asap, inherently accounts for ballot duration, so this is 9 days
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );

        // Confirm the configuration is queued
        expectedTimestamp += 1;
        JBFundingCycle memory queued = jbFundingCycleStore().queuedOf(projectId);

        assertEq(queued.number, 2);
        assertEq(queued.configuration, expectedTimestamp);
        assertEq(queued.weight, weightFirstReconfiguration);

        // Will follow the rolledover (FC #1) cycle, after overriding the above config, bc first reconfig is in ApprovalExpected status (3 days ballot has not passed)
        // FC #1 rolls over bc our mustStartAtOrAfter occurs later than when FC #1 ends.
        vm.prank(multisig());
        controller.reconfigureFundingCyclesOf(
            projectId,
            JBFundingCycleData({duration: 6 days, weight: weightSecondReconfiguration, discountRate: 0, ballot: JBReconfigurationBufferBallot(_ballot)}), // 3days ballot
            _metadata,
            block.timestamp + 9 days, // Starts 3 days into FC #2
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );

        // Confirm that this latest reconfiguration implies a rolled over cycle of FC #1.
        expectedTimestamp += 1;
        JBFundingCycle memory requeued = jbFundingCycleStore().queuedOf(projectId);

        assertEq(requeued.number, 2);
        assertEq(requeued.configuration, initialTimestamp);
        assertEq(requeued.weight, weightInitial);

        // Warp to when the initial configuration rolls over and again becomes the current
        vm.warp(block.timestamp + 6 days);

        // Rolled over configuration
        JBFundingCycle memory initialIsCurrent = jbFundingCycleStore().currentOf(projectId);
        assertEq(initialIsCurrent.number, 2);
        assertEq(initialIsCurrent.configuration, initialTimestamp);
        assertEq(initialIsCurrent.weight, weightInitial);

        // Queued second reconfiguration that replaced our first reconfiguration
        JBFundingCycle memory requeued2 = jbFundingCycleStore().queuedOf(projectId);
        assertEq(requeued2.number, 3);
        assertEq(requeued2.configuration, expectedTimestamp);
        assertEq(requeued2.weight, weightSecondReconfiguration);
    }

    function testSingleBlockOverwriteQueued() public {
        uint256 weightFirstReconfiguration = 1234 * 10 ** 18;
        uint256 weightSecondReconfiguration = 6969 * 10 ** 18;

        // Keep a reference to the expected timestamp after reconfigurations, starting now, incremented later in-line for readability.
        uint256 expectedTimestamp = block.timestamp;

        uint256 projectId = controller.launchProjectFor(
            multisig(),
            _projectMetadata,
            _data,
            _metadata,
            0, // Start asap
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        JBFundingCycle memory fundingCycle = jbFundingCycleStore().currentOf(projectId);

        // Initial funding cycle data: will have a block.timestamp (configuration) that is 2 less than the second reconfiguration (timestamps are incremented when queued in same block now)
        assertEq(fundingCycle.number, 1);
        assertEq(fundingCycle.weight, _data.weight);

        // Becomes queued & will be overwritten as 3 days will not pass and it's status is "ApprovalExpected"
        vm.prank(multisig());
        controller.reconfigureFundingCyclesOf(
            projectId,
            JBFundingCycleData({duration: 6 days, weight: weightFirstReconfiguration, discountRate: 0, ballot: JBReconfigurationBufferBallot(_ballot)}), // 3days ballot
            _metadata,
            block.timestamp + 3 days,
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );

        expectedTimestamp += 1;

        JBFundingCycle memory queuedToOverwrite = jbFundingCycleStore().queuedOf(projectId);

        assertEq(queuedToOverwrite.number, 2);
        assertEq(queuedToOverwrite.configuration, expectedTimestamp);
        assertEq(queuedToOverwrite.weight, weightFirstReconfiguration);

        // overwriting reconfiguration
        vm.prank(multisig());
        controller.reconfigureFundingCyclesOf(
            projectId,
            JBFundingCycleData({duration: 6 days, weight: weightSecondReconfiguration, discountRate: 0, ballot: JBReconfigurationBufferBallot(address(0))}), // 3days ballot
            _metadata,
            block.timestamp + 3 days,
            _groupedSplits,
            _fundAccessConstraints,
            ""
        );

        expectedTimestamp += 1;

        JBFundingCycle memory queued = jbFundingCycleStore().queuedOf(projectId);

        assertEq(queued.number, 2);
        assertEq(queued.configuration, expectedTimestamp);
        assertEq(queued.weight, weightSecondReconfiguration);

    }
}
