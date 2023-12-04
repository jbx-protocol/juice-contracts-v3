// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// Projects can be launched.
contract TestLaunchProject_Local is TestBaseWorkflow {
    IJBController private _controller;
    JBRulesetData private _data;
    JBRulesetMetadata private _metadata;
    IJBTerminal private _terminal;
    IJBRulesets private _rulesets;

    address private _projectOwner;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _terminal = jbMultiTerminal();
        _controller = jbController();
        _rulesets = jbRulesets();

        _data = JBRulesetData({
            duration: 0,
            weight: 0,
            decayRate: 0,
            approvalHook: IJBRulesetApprovalHook(address(0))
        });

        _metadata = JBRulesetMetadata({
            reservedRate: 0,
            redemptionRate: 0,
            baseCurrency: uint32(uint160(JBTokenList.Native)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowDiscretionaryMinting: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowControllerMigration: false,
            allowSetController: false,
            holdFees: false,
            useTotalSurplusForRedemptions: false,
            useDataHookForPay: false,
            useDataHookForRedeem: false,
            dataHook: address(0),
            metadata: 0
        });
    }

    function equals(JBRuleset memory configured, JBRuleset memory stored)
        internal
        view
        returns (bool)
    {
        // Just compare the output of hashing all fields packed.
        return (
            keccak256(
                abi.encodePacked(
                    configured.cycleNumber,
                    configured.rulesetId,
                    configured.basedOnId,
                    configured.start,
                    configured.duration,
                    configured.weight,
                    configured.decayRate,
                    configured.approvalHook,
                    configured.metadata
                )
            )
                == keccak256(
                    abi.encodePacked(
                        stored.cycleNumber,
                        stored.rulesetId,
                        stored.basedOnId,
                        stored.start,
                        stored.duration,
                        stored.weight,
                        stored.decayRate,
                        stored.approvalHook,
                        stored.metadata
                    )
                )
        );
    }

    function testLaunchProject() public {
        // Package up ruleset configuration.
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = new JBSplitGroup[](0);
        _rulesetConfig[0].fundAccessLimitGroup = new JBFundAccessLimitGroup[](0);

        // Package up terminal configuration.
        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
        _accountingContexts[0] = JBAccountingContextConfig({
            token: JBTokenList.Native,
            standard: JBTokenStandards.NATIVE
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        uint256 projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            rulesetConfigurations: _rulesetConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        // Get a reference to the first ruleset.
        JBRuleset memory ruleset = _rulesets.currentOf(projectId);

        // Reference configured attributes for sake of comparison.
        JBRuleset memory configured = JBRuleset({
            cycleNumber: 1,
            rulesetId: block.timestamp,
            basedOnId: 0,
            start: block.timestamp,
            duration: _data.duration,
            weight: _data.weight,
            decayRate: _data.decayRate,
            approvalHook: _data.approvalHook,
            metadata: ruleset.metadata
        });

        bool same = equals(configured, ruleset);

        assertEq(same, true);
    }

    function testLaunchProjectFuzzWeight(uint256 _weight) public {
        _weight = bound(_weight, 0, type(uint88).max);
        uint256 _projectId;

        _data = JBRulesetData({
            duration: 14,
            weight: _weight,
            decayRate: 450_000_000,
            approvalHook: IJBRulesetApprovalHook(address(0))
        });

        // Package up ruleset configuration.
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = new JBSplitGroup[](0);
        _rulesetConfig[0].fundAccessLimitGroup = new JBFundAccessLimitGroup[](0);

        // Package up terminal configuration.
        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
        _accountingContexts[0] = JBAccountingContextConfig({
            token: JBTokenList.Native,
            standard: JBTokenStandards.NATIVE
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            rulesetConfigurations: _rulesetConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        JBRuleset memory ruleset = _rulesets.currentOf(_projectId);

        // Reference configured attributes for sake of comparison.
        JBRuleset memory configured = JBRuleset({
            cycleNumber: 1,
            rulesetId: block.timestamp,
            basedOnId: 0,
            start: block.timestamp,
            duration: _data.duration,
            weight: _weight,
            decayRate: _data.decayRate,
            approvalHook: _data.approvalHook,
            metadata: ruleset.metadata
        });

        bool same = equals(configured, ruleset);

        assertEq(same, true);
    }

    function testLaunchOverweight(uint256 _weight) public {
        _weight = bound(_weight, type(uint88).max, type(uint256).max);
        uint256 _projectId;

        _data = JBRulesetData({
            duration: 14,
            weight: _weight,
            decayRate: 450_000_000,
            approvalHook: IJBRulesetApprovalHook(address(0))
        });

        // Package up ruleset configuration.
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = new JBSplitGroup[](0);
        _rulesetConfig[0].fundAccessLimitGroup = new JBFundAccessLimitGroup[](0);

        // Package up terminal configuration.
        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](1);
        _accountingContexts[0] = JBAccountingContextConfig({
            token: JBTokenList.Native,
            standard: JBTokenStandards.NATIVE
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        if (_weight > type(uint88).max) {
            // `expectRevert` on the next call if weight overflowing.
            vm.expectRevert(abi.encodeWithSignature("INVALID_WEIGHT()"));

            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: "myIPFSHash",
                rulesetConfigurations: _rulesetConfig,
                terminalConfigurations: _terminalConfigurations,
                memo: ""
            });
        } else {
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: "myIPFSHash",
                rulesetConfigurations: _rulesetConfig,
                terminalConfigurations: _terminalConfigurations,
                memo: ""
            });

            // Reference for sake of comparison.
            JBRuleset memory ruleset = _rulesets.currentOf(_projectId);

            // Reference configured attributes for sake of comparison.
            JBRuleset memory configured = JBRuleset({
                cycleNumber: 1,
                rulesetId: block.timestamp,
                basedOnId: 0,
                start: block.timestamp,
                duration: _data.duration,
                weight: _weight,
                decayRate: _data.decayRate,
                approvalHook: _data.approvalHook,
                metadata: ruleset.metadata
            });

            bool same = equals(configured, ruleset);

            assertEq(same, true);
        }
    }
}
