// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";

contract TestSplitStore_Local is TestBaseWorkflow {
    IJBController3_1 private _controller;
    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;
    IJBMultiTerminal private _terminal;
    IJBOperatorStore private _opStore;
    IJBProjects private _projects;
    IJBTokenStore private _tokenStore;

    address private _projectOwner;
    address payable private _splitsGuy;
    uint256 private _projectId;
    uint256 _ethDistributionLimit = 4 ether;
    uint256 _ethPricePerUsd = 0.0005 * 10 ** 18; // 1/2000
    uint256 _usdDistributionLimit = PRBMath.mulDiv(1 ether, 10 ** 18, _ethPricePerUsd);

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _terminal = jbPayoutRedemptionTerminal();
        _controller = jbController();
        _opStore = jbOperatorStore();
        _projects = jbProjects();
        _tokenStore = jbTokenStore();
        _splitsGuy = payable(makeAddr("guy"));

        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        _data = JBFundingCycleData({
            duration: 3 days,
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

        // Instantiate split parameters.
        JBGroupedSplits[] memory _splitsGroup = new JBGroupedSplits[](3);
        JBSplit[] memory _splits = new JBSplit[](2);
        JBSplit[] memory _reserveRateSplits = new JBSplit[](1);

        // Configure a payout split recipient.
        _splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT / 2,
            projectId: 0,
            beneficiary: _splitsGuy,
            lockedUntil: 0,
            allocator: IJBSplitAllocator(address(0))
        });

        // A dummy used to check that splits groups of "0" don't bypass distribution limits.
        _splits[1] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT / 2,
            projectId: 0,
            beneficiary: _splitsGuy,
            lockedUntil: 0,
            allocator: IJBSplitAllocator(address(0))
        });

        _splitsGroup[0] = JBGroupedSplits({
            group: uint32(uint160(JBTokens.ETH)),
            splits: _splits
        });

        // A dummy used to check that splits groups of "0" don't bypass distribution limits.
        _splitsGroup[1] = JBGroupedSplits({
            group: 0,
            splits: _splits
        });

        // Configure a reserve rate split recipient.
        _reserveRateSplits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT,
            projectId: 0,
            beneficiary: _splitsGuy,
            lockedUntil: 0,
            allocator: IJBSplitAllocator(address(0))
        });

        // Reserved rate split group
        _splitsGroup[2] = JBGroupedSplits({
            group: JBSplitsGroups.RESERVED_TOKENS,
            splits: _reserveRateSplits
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

        // dummy project to receive fees
        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: _projectMetadata,
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: _projectMetadata,
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testSplitPayoutAndReservedRateSplit() public {
        uint256 _ethPayAmount = 10 ether;
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
            amount: _ethDistributionLimit,
            currency: uint32(uint160(JBTokens.ETH)),
            token: JBTokens.ETH, // unused
            minReturnedTokens: 0
        });

        // Calculate the amount returned after fees are processed
        uint256 _beneficiaryEthBalance = PRBMath.mulDiv(
            _ethDistributionLimit,
            JBConstants.MAX_FEE,
            JBConstants.MAX_FEE + _terminal.FEE()
        );

        assertEq(_splitsGuy.balance, _beneficiaryEthBalance);

        // Check that split groups of "0" don't extend distribution limit (keeping this out of a number test, for brevity)
        vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));

        // First dist meets our ETH limit
        _terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _ethDistributionLimit,
            currency: uint32(uint160(JBTokens.ETH)),
            token: JBTokens.ETH, // unused
            minReturnedTokens: 0
        });

        vm.prank(_projectOwner);
        _controller.distributeReservedTokensOf(_projectId, "");

        // 10 Ether paid -> 1000 per Eth, 10000 total, 50% reserve rate, 5000 tokens distributed
        uint256 _reserveRateDistributionAmount = PRBMath.mulDiv(
            _ethPayAmount, _data.weight, 10 ** 18
        ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;

        assertEq(_tokenStore.balanceOf(_splitsGuy, _projectId), _reserveRateDistributionAmount);
    }

    function testFuzzedSplitConfiguration(uint256 _currencyId, uint256 _multiplier) public {
        _currencyId = bound(_currencyId, 0, type(uint32).max);
        _multiplier = bound(_multiplier, 2, JBConstants.SPLITS_TOTAL_PERCENT);

        // Instantiate split parameters.
        JBGroupedSplits[] memory _splitsGroup = new JBGroupedSplits[](2);
        JBSplit[] memory _splits = new JBSplit[](2);

        // Configure a payout split recipient.
        _splits[0] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT / _multiplier,
            projectId: 0,
            beneficiary: _splitsGuy,
            lockedUntil: 0,
            allocator: IJBSplitAllocator(address(0))
        });

        // A dummy used to check that splits groups of "0" don't bypass distribution limits.
        _splits[1] = JBSplit({
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT / _multiplier,
            projectId: 0,
            beneficiary: _splitsGuy,
            lockedUntil: 0,
            allocator: IJBSplitAllocator(address(0))
        });

        _splitsGroup[0] = JBGroupedSplits({
            group: _currencyId,
            splits: _splits
        });

        // Package up fund access constraints
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);

        _distributionLimits[0] = JBCurrencyAmount({
            value: _ethDistributionLimit,
            currency: _currencyId
        });
        _overflowAllowances[0] =
            JBCurrencyAmount({value: 2 ether, currency: _currencyId});
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

        // dummy project to receive fees
        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: _projectMetadata,
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

}