// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

contract TestOperatorStore_Local is TestBaseWorkflow {
    IJBController3_1 private _controller;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;
    IJBTerminal private _terminal;
    IJBOperatorStore private _opStore;

    address private _projectOwner;
    uint256 private _projectZero;
    uint256 private _projectOne;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _terminal = jbPayoutRedemptionTerminal();
        _controller = jbController();
        _opStore = jbOperatorStore();

        _data = JBFundingCycleData({
            duration: 0,
            weight: 0,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
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

        _projectZero = _controller.launchProjectFor({
            owner: makeAddr("zeroOwner"),
            projectMetadata: "myIPFSHash",
            rulesetConfigurations: _rulesetConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        _projectOne = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            rulesetConfigurations: _rulesetConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testFailMostBasicAccess() public {
        // Package up cycle config.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
        _cycleConfig[0].fundAccessConstraints = new JBFundAccessConstraints[](0);

        vm.prank(makeAddr("zeroOwner"));
        uint256 configured = _controller.reconfigureFundingCyclesOf(_projectOne, _cycleConfig, "");

        assertEq(configured, block.timestamp);
    }

    function testFailSetOperators() public {
        // Pack up our permission data
        JBOperatorData[] memory opData = new JBOperatorData[](1);

        uint256[] memory permIndexes = new uint256[](257);

        // Push an index higher than 255
        for (uint256 i; i < 257; i++) {
            permIndexes[i] = i;

            opData[0] = JBOperatorData({
                operator: address(0),
                domain: _projectOne,
                permissionIndexes: permIndexes
            });

            // Set em.
            vm.prank(_projectOwner);
            _opStore.setOperatorOf(_projectOwner, opData[0]);
        }
    }

    function testSetOperators() public {
        // Pack up our permission data
        JBOperatorData[] memory opData = new JBOperatorData[](1);

        uint256[] memory permIndexes = new uint256[](256);

        // Push an index higher than 255
        for (uint256 i; i < 256; i++) {
            permIndexes[i] = i;

            opData[0] = JBOperatorData({
                operator: address(0),
                domain: _projectOne,
                permissionIndexes: permIndexes
            });

            // Set em.
            vm.prank(_projectOwner);
            _opStore.setOperatorOf(_projectOwner, opData[0]);

            // verify
            bool _check =
                _opStore.hasPermission(address(0), _projectOwner, _projectOne, permIndexes[i]);
            assertEq(_check, true);
        }
    }

    /* function testBasicAccessSetup() public {
        vm.prank(address(_projectOwner));
        bool _check = _opStore.hasPermission(address(_projectOwner), address(_projectOwner), 0, 2);

        assertEq(_check, true);
    } */
}
