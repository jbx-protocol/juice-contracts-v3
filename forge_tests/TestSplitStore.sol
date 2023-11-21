// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

contract TestSplitStore_Local is TestBaseWorkflow {
    IJBController3_1 private _controller;
    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;
    IJBPaymentTerminal private _terminal;
    IJBOperatorStore private _opStore;
    IJBProjects private _projects;

    address private _projectOwner;
    address payable private _splitsGuy;
    uint256 private _projectId;
    uint256 _ethDistributionLimit = 2 ether;
    uint256 _ethPricePerUsd = 0.0005 * 10 ** 18; // 1/2000
    uint256 _usdDistributionLimit = PRBMath.mulDiv(1 ether, 10 ** 18, _ethPricePerUsd);

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _terminal = jbPayoutRedemptionTerminal();
        _controller = jbController();
        _opStore = jbOperatorStore();
        _projects = jbProjects();
        _splitsGuy = payable(makeAddr("guy"));

        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        _data = JBFundingCycleData({
            duration: 3 days,
            weight: 0,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: JBConstants.MAX_RESERVED_RATE / 2,
            redemptionRate: 0,
            baseCurrency: uint32(uint160(JBTokens.ETH)),
            pausePay: false,
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

        JBGroupedSplits[] memory _splitsGroup = new JBGroupedSplits[](1);
        JBSplit[] memory _splits = new JBSplit[](1);

        _splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 1,
            beneficiary: _splitsGuy,
            lockedUntil: 0,
            allocator: IJBSplitAllocator(address(0))
        });

        _splitsGroup[0] = JBGroupedSplits({
            group: 61166,
            splits: _splits
        });

        // Package up fund access constraints
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);

        _distributionLimits[0] = JBCurrencyAmount({
            value: _ethDistributionLimit,
            currency: uint32(uint160(JBTokens.ETH))
        });
        _overflowAllowances[0] =
            JBCurrencyAmount({value: 2 ether, currency: uint32(uint160(JBTokens.ETH))});
        _fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: _terminal,
            token: JBTokens.ETH,
            distributionLimits: _distributionLimits,
            overflowAllowances: _overflowAllowances
        });

        // Package up cycle config.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _splitsGroup;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

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
    }

    function testBasicSplitPayout() public {
        uint256 _ethPayAmount = 4 ether;
        address _payee = makeAddr("payee");
        vm.deal(_payee, _ethPayAmount);
        vm.prank(_payee);

        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokens.ETH,
            beneficiary: _payee,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: new bytes(0)
        });

        // First dist meets our ETH limit
        _terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: 2 ether,
            currency: uint32(uint160(JBTokens.ETH)),
            token: JBTokens.ETH, // unused
            minReturnedTokens: 0
        });

        assertEq(_splitsGuy.balance, 1 ether);
    }

}