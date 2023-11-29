// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

// Projects can be launched.
contract TestLaunchProject_Local is TestBaseWorkflow {
    IJBController3_1 private _controller;
    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;
    IJBPaymentTerminal private _terminal;
    IJBFundingCycleStore private _fcStore;

    address private _projectOwner;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _terminal = jbPayoutRedemptionTerminal();
        _controller = jbController();
        _fcStore = jbFundingCycleStore();

        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        _data = JBFundingCycleData({
            duration: 0,
            weight: 0,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({allowSetTerminals: false, allowSetController: false}),
            reservedRate: 0,
            redemptionRate: 0,
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
            pauseTokenCreditTransfers: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(0),
            metadata: 0
        });
    }

    function equals(JBFundingCycle memory configured, JBFundingCycle memory stored)
        internal
        view
        returns (bool)
    {
        // Just compare the output of hashing all fields packed
        return (
            keccak256(
                abi.encodePacked(
                    configured.number,
                    configured.configuration,
                    configured.basedOn,
                    configured.start,
                    configured.duration,
                    configured.weight,
                    configured.discountRate,
                    configured.ballot,
                    configured.metadata
                )
            )
                == keccak256(
                    abi.encodePacked(
                        stored.number,
                        stored.configuration,
                        stored.basedOn,
                        stored.start,
                        stored.duration,
                        stored.weight,
                        stored.discountRate,
                        stored.ballot,
                        stored.metadata
                    )
                )
        );
    }

    function testLaunchProject() public {
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
            owner: _projectOwner,
            projectMetadata: _projectMetadata,
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        // Get a reference to the first funding cycle.
        JBFundingCycle memory fundingCycle = _fcStore.currentOf(projectId);

        // Reference configured attributes for sake of comparison
        JBFundingCycle memory configured = JBFundingCycle({
            number: 1,
            configuration: block.timestamp,
            basedOn: 0,
            start: block.timestamp,
            duration: _data.duration,
            weight: _data.weight,
            discountRate: _data.discountRate,
            ballot: _data.ballot,
            metadata: fundingCycle.metadata
        });

        bool same = equals(configured, fundingCycle);

        assertEq(same, true);
    }

    function testLaunchProjectFuzzWeight(uint256 _weight) public {
        _weight = bound(_weight, 0, type(uint88).max);
        uint256 _projectId;

        _data = JBFundingCycleData({
            duration: 14,
            weight: _weight,
            discountRate: 450_000_000,
            ballot: IJBFundingCycleBallot(address(0))
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

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: _projectMetadata,
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        JBFundingCycle memory fundingCycle = _fcStore.currentOf(_projectId);

        // Reference configured attributes for sake of comparison
        JBFundingCycle memory configured = JBFundingCycle({
            number: 1,
            configuration: block.timestamp,
            basedOn: 0,
            start: block.timestamp,
            duration: _data.duration,
            weight: _weight,
            discountRate: _data.discountRate,
            ballot: _data.ballot,
            metadata: fundingCycle.metadata
        });

        bool same = equals(configured, fundingCycle);

        assertEq(same, true);
    }

    function testLaunchOverweight(uint256 _weight) public {
        _weight = bound(_weight, type(uint88).max, type(uint256).max);
        uint256 _projectId;

        _data = JBFundingCycleData({
            duration: 14,
            weight: _weight,
            discountRate: 450_000_000,
            ballot: IJBFundingCycleBallot(address(0))
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

        if (_weight > type(uint88).max) {
            // expectRevert on the next call if weight overflowing
            vm.expectRevert(abi.encodeWithSignature("INVALID_WEIGHT()"));

            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: _projectMetadata,
                fundingCycleConfigurations: _cycleConfig,
                terminalConfigurations: _terminalConfigurations,
                memo: ""
            });
        } else {
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: _projectMetadata,
                fundingCycleConfigurations: _cycleConfig,
                terminalConfigurations: _terminalConfigurations,
                memo: ""
            });

            // Reference for sake of comparison
            JBFundingCycle memory fundingCycle = _fcStore.currentOf(_projectId);

            // Reference configured attributes for sake of comparison
            JBFundingCycle memory configured = JBFundingCycle({
                number: 1,
                configuration: block.timestamp,
                basedOn: 0,
                start: block.timestamp,
                duration: _data.duration,
                weight: _weight,
                discountRate: _data.discountRate,
                ballot: _data.ballot,
                metadata: fundingCycle.metadata
            });

            bool same = equals(configured, fundingCycle);

            assertEq(same, true);
        }
    }
}
