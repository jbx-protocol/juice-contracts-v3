// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

contract TestPermissions_Local is TestBaseWorkflow {
    IJBController private _controller;
    JBProjectMetadata private _projectMetadata;
    JBRulesetData private _data;
    JBRulesetMetadata private _metadata;
    IJBTerminal private _terminal;
    IJBPermissions private _permissions;

    address private _projectOwner;
    uint256 private _projectZero;
    uint256 private _projectOne;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _terminal = jbPayoutRedemptionTerminal();
        _controller = jbController();
        _permissions = jbPermissions();

        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        _data = JBRulesetData({
            duration: 0,
            weight: 0,
            decayRate: 0,
            approvalHook: IJBRulesetApprovalHook(address(0))
        });

        _metadata = JBRulesetMetadata({
            global: JBGlobalRulesetMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: 0,
            redemptionRate: 0,
            baseCurrency: uint32(uint160(JBTokenList.ETH)),
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
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokenList.ETH, standard: JBTokenStandards.NATIVE});
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _terminal, accountingContextConfigs: _accountingContexts});

        _projectZero = _controller.launchProjectFor({
            owner: makeAddr("zeroOwner"),
            projectMetadata: _projectMetadata,
            rulesetConfigurations: _rulesetConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        _projectOne = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: _projectMetadata,
            rulesetConfigurations: _rulesetConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testFailMostBasicAccess() public {
        // Package up cycle config.
        JBRulesetConfig[] memory _rulesetConfig = new JBRulesetConfig[](1);
        _rulesetConfig[0].mustStartAtOrAfter = 0;
        _rulesetConfig[0].data = _data;
        _rulesetConfig[0].metadata = _metadata;
        _rulesetConfig[0].splitGroups = new JBSplitGroup[](0);
        _rulesetConfig[0].fundAccessLimitGroup = new JBFundAccessLimitGroup[](0);

        vm.prank(makeAddr("zeroOwner"));
        uint256 configured = _controller.queueRulesetsOf(_projectOne, _rulesetConfig, "");

        assertEq(configured, block.timestamp);
    }

    function testFailSetOperators() public {
        // Pack up our permission data
        JBPermissionsData[] memory opData = new JBPermissionsData[](1);

        uint256[] memory permIds = new uint256[](257);

        // Push an index higher than 255
        for (uint256 i; i < 257; i++) {
            permIds[i] = i;

            opData[0] = JBPermissionsData({
                operator: address(0),
                projectId: _projectOne,
                permissionIds: permIds
            });

            // Set em.
            vm.prank(_projectOwner);
            _permissions.setPermissionsForOperator(_projectOwner, opData[0]);
        }
    }

    function testSetOperators() public {
        // Pack up our permission data
        JBPermissionsData[] memory opData = new JBPermissionsData[](1);

        uint256[] memory permIds = new uint256[](256);

        // Push an index higher than 255
        for (uint256 i; i < 256; i++) {
            permIds[i] = i;

            opData[0] = JBPermissionsData({
                operator: address(0),
                projectId: _projectOne,
                permissionIds: permIds
            });

            // Set em.
            vm.prank(_projectOwner);
            _permissions.setPermissionsForOperator(_projectOwner, opData[0]);

            // verify
            bool _check =
                _permissions.hasPermission(address(0), _projectOwner, _projectOne, permIds[i]);
            assertEq(_check, true);
        }
    }

    /* function testBasicAccessSetup() public {
        vm.prank(address(_projectOwner));
        bool _check = _permissions.hasPermission(address(_projectOwner), address(_projectOwner), 0, 2);

        assertEq(_check, true);
    } */
}
