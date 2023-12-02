// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";
import {MockPriceFeed} from "./mock/MockPriceFeed.sol";

contract TestMultipleAccessLimits_Local is TestBaseWorkflow {
    uint256 private _ethCurrency;
    IJBController3_1 private _controller;
    IJBMultiTerminal private __terminal;
    IJBPrices private _prices;
    JBTokenStore private _tokenStore;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata _metadata;
    JBGroupedSplits[] private _groupedSplits;
    address private _projectOwner;
    address private _beneficiary;

    function setUp() public override {
        super.setUp();

        _ethCurrency = uint32(uint160(JBTokens.ETH));
        _controller = jbController();
        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _prices = jbPrices();
        __terminal = jbPayoutRedemptionTerminal();
        _tokenStore = jbTokenStore();
        _data = JBFundingCycleData({
            duration: 0,
            weight: 1000 * 10 ** 18,
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
    }

    function launchProjectsForTestBelow()
        public
        returns (uint256, JBCurrencyAmount[] memory, JBAccountingContextConfig[] memory)
    {
        uint256 _ethPayAmount = 1.5 ether;
        uint256 _ethDistributionLimit = 1 ether;
        uint256 _ethPricePerUsd = 0.0005 * 10 ** 18; // 1/2000
        // More than the treasury will have available.
        uint256 _usdDistributionLimit = PRBMath.mulDiv(1 ether, 10 ** 18, _ethPricePerUsd);

        // Package up fund access constraints
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](2);
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);

        _distributionLimits[0] = JBCurrencyAmount({
            value: _ethDistributionLimit,
            currency: uint32(uint160(JBTokens.ETH))
        });
        _distributionLimits[1] = JBCurrencyAmount({
            value: _usdDistributionLimit,
            currency: uint32(uint160(address(usdcToken())))
        });
        _overflowAllowances[0] =
            JBCurrencyAmount({value: 1 ether, currency: uint32(uint160(JBTokens.ETH))});
        _fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: address(__terminal),
            token: JBTokens.ETH,
            distributionLimits: _distributionLimits,
            overflowAllowances: _overflowAllowances
        });

        // Package up cycle config.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](2);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _accountingContexts[1] = JBAccountingContextConfig({
            token: address(usdcToken()),
            standard: JBTokenStandards.ERC20
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: __terminal, accountingContextConfigs: _accountingContexts});

        // dummy
        _controller.launchProjectFor({
            owner: address(420), //random
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        uint256 _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        vm.startPrank(_projectOwner);
        MockPriceFeed _priceFeedEthUsd = new MockPriceFeed(_ethPricePerUsd, 18);
        vm.label(address(_priceFeedEthUsd), "MockPrice Feed ETH-USD");

        _prices.addFeedFor({
            projectId: _projectId,
            currency: uint32(uint160(JBTokens.ETH)),
            base: uint32(uint160(address(usdcToken()))),
            priceFeed: _priceFeedEthUsd
        });

        vm.stopPrank();

        return (_projectId, _distributionLimits, _accountingContexts);
    }

    function testAccessConstraintsDelineation() external {
        uint256 _ethPayAmount = 1.5 ether;
        uint256 _ethDistributionLimit = 1 ether;
        uint256 _ethPricePerUsd = 0.0005 * 10 ** 18; // 1/2000
        // More than the treasury will have available.
        uint256 _usdDistributionLimit = PRBMath.mulDiv(1 ether, 10 ** 18, _ethPricePerUsd);

        (
            uint256 _projectId,
            JBCurrencyAmount[] memory _distributionLimits,
            JBAccountingContextConfig[] memory _accountingContexts
        ) = launchProjectsForTestBelow();

        __terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokens.ETH,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: new bytes(0)
        });

        uint256 initTerminalBalance = address(__terminal).balance;

        // Make sure the beneficiary has a balance of JBTokens.
        assertEq(
            _tokenStore.balanceOf(_beneficiary, _projectId),
            PRBMathUD60x18.mul(_ethPayAmount, _data.weight)
        );

        // First dist meets our ETH limit
        __terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _ethDistributionLimit,
            currency: uint32(uint160(JBTokens.ETH)),
            token: JBTokens.ETH, // unused
            minReturnedTokens: 0
        });

        // Make sure the balance has changed, accounting for the fee that stays.
        assertEq(
            address(__terminal).balance,
            initTerminalBalance
                - PRBMath.mulDiv(
                    _distributionLimits[0].value,
                    JBConstants.MAX_FEE,
                    JBConstants.MAX_FEE + __terminal.FEE()
                )
        );

        // Price for the amount (in USD) that is distributable based on the terminals current balance
        uint256 _usdDistributableAmount = PRBMath.mulDiv(
            _ethPayAmount - _ethDistributionLimit, // ETH value
            10 ** 18, // Use _MAX_FIXED_POINT_FIDELITY to keep as much of the `_amount.value`'s fidelity as possible when converting.
            _prices.priceFor({
                projectId: _projectId,
                currency: _ethCurrency,
                base: uint32(uint160(address(usdcToken()))),
                decimals: 18
            })
        );

        /* vm.prank(address(__terminal));
        vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        // add 10000 to make up for the fidelity difference in prices. (0.0005/1)
        jbTerminalStore().recordDistributionFor(_projectId, _accountingContexts[1], _usdDistributableAmount + 10000, uint32(uint160(address(usdcToken())))); */

        // Should succeed with _distributableAmount
        __terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _usdDistributableAmount,
            currency: uint32(uint160(address(usdcToken()))),
            token: JBTokens.ETH, // token
            minReturnedTokens: 0
        });

        // Pay in another allotment.
        vm.deal(_beneficiary, _ethPayAmount);
        vm.prank(_beneficiary);

        __terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokens.ETH, // unused
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: new bytes(0)
        });

        /*  // Trying to distribute via our ETH distLimit will fail (currency is ETH or 1)
        vm.prank(address(__terminal));
        vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
        jbTerminalStore().recordDistributionFor(_projectId, _accountingContexts[0], 1, _ethCurrency); */

        // But distribution via USD limit will succeed
        __terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _usdDistributableAmount,
            currency: uint32(uint160(address(usdcToken()))),
            token: JBTokens.ETH, //token (unused)
            minReturnedTokens: 0
        });
    }

    function testFuzzedInvalidAllowanceCurrencyOrdering(uint24 ALLOWCURRENCY) external {
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](2);

        _distributionLimits[0] = JBCurrencyAmount({value: 1, currency: _ethCurrency});

        _overflowAllowances[0] = JBCurrencyAmount({value: 1, currency: ALLOWCURRENCY});

        _overflowAllowances[1] =
            JBCurrencyAmount({value: 1, currency: ALLOWCURRENCY == 0 ? 0 : ALLOWCURRENCY - 1});

        _fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: address(__terminal),
            token: JBTokens.ETH,
            distributionLimits: _distributionLimits,
            overflowAllowances: _overflowAllowances
        });

        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);

        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        _projectOwner = multisig();

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](2);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _accountingContexts[1] = JBAccountingContextConfig({
            token: address(usdcToken()),
            standard: JBTokenStandards.ERC20
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: __terminal, accountingContextConfigs: _accountingContexts});

        vm.prank(_projectOwner);

        vm.expectRevert(abi.encodeWithSignature("INVALID_OVERFLOW_ALLOWANCE_CURRENCY_ORDERING()"));

        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testFuzzedInvalidDistCurrencyOrdering(uint24 _distributionCurrency) external {
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](2);
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);

        _distributionLimits[0] = JBCurrencyAmount({value: 1, currency: _distributionCurrency});

        _distributionLimits[1] = JBCurrencyAmount({
            value: 1,
            currency: _distributionCurrency == 0 ? 0 : _distributionCurrency - 1
        });

        _overflowAllowances[0] = JBCurrencyAmount({value: 1, currency: 1});

        _fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: address(__terminal),
            token: JBTokens.ETH,
            distributionLimits: _distributionLimits,
            overflowAllowances: _overflowAllowances
        });

        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);

        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        _projectOwner = multisig();

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](2);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _accountingContexts[1] = JBAccountingContextConfig({
            token: address(usdcToken()),
            standard: JBTokenStandards.ERC20
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: __terminal, accountingContextConfigs: _accountingContexts});

        vm.prank(_projectOwner);

        vm.expectRevert(abi.encodeWithSignature("INVALID_DISTRIBUTION_LIMIT_CURRENCY_ORDERING()"));

        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testFuzzedConfigureAccess(
        uint256 _distributionLimit,
        uint256 _allowanceLimit,
        uint256 _distributionCurrency,
        uint256 ALLOWCURRENCY
    ) external {
        _distributionCurrency =
            bound(uint256(_distributionCurrency), uint256(0), type(uint24).max - 1);
        _distributionLimit =
            bound(uint256(_distributionLimit), uint232(1), uint232(type(uint24).max - 1));
        _allowanceLimit = bound(uint256(_allowanceLimit), uint232(1), uint232(type(uint24).max - 1));
        ALLOWCURRENCY = bound(uint256(ALLOWCURRENCY), uint256(0), type(uint24).max - 1);

        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](2);
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](2);

        _distributionLimits[0] =
            JBCurrencyAmount({value: _distributionLimit, currency: _distributionCurrency});

        _distributionLimits[1] =
            JBCurrencyAmount({value: _distributionLimit, currency: _distributionCurrency + 1});
        _overflowAllowances[0] = JBCurrencyAmount({value: _allowanceLimit, currency: ALLOWCURRENCY});
        _overflowAllowances[1] =
            JBCurrencyAmount({value: _allowanceLimit, currency: ALLOWCURRENCY + 1});
        _fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: address(__terminal),
            token: JBTokens.ETH,
            distributionLimits: _distributionLimits,
            overflowAllowances: _overflowAllowances
        });
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](2);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _accountingContexts[1] = JBAccountingContextConfig({
            token: address(usdcToken()),
            standard: JBTokenStandards.ERC20
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: __terminal, accountingContextConfigs: _accountingContexts});

        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });
    }

    function testFailMultipleDistroLimitCurrenciesOverLimit() external {
        uint256 _ethPayAmount = 1.5 ether;
        uint256 _ethDistributionLimit = 1 ether;
        uint256 _ethPricePerUsd = 0.0005 * 10 ** 18; // 1/2000
        // More than the treasury will have available.
        uint256 _usdDistributionLimit = PRBMath.mulDiv(1 ether, 10 ** 18, _ethPricePerUsd);

        // Package up fund access constraints
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](2);
        JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);

        _distributionLimits[0] =
            JBCurrencyAmount({value: _ethDistributionLimit, currency: _ethCurrency});
        _distributionLimits[1] = JBCurrencyAmount({
            value: _usdDistributionLimit,
            currency: uint32(uint160(address(usdcToken())))
        });
        _overflowAllowances[0] = JBCurrencyAmount({value: 1, currency: 1});
        _fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: address(__terminal),
            token: JBTokens.ETH,
            distributionLimits: _distributionLimits,
            overflowAllowances: _overflowAllowances
        });

        // Package up cycle config.
        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);
        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](2);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _accountingContexts[1] = JBAccountingContextConfig({
            token: address(usdcToken()),
            standard: JBTokenStandards.ERC20
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: __terminal, accountingContextConfigs: _accountingContexts});

        // dummy
        _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        uint256 _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        __terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokens.ETH, // unused
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: new bytes(0)
        });

        // Make sure beneficiary has a balance of JBTokens
        uint256 _userTokenBalance = PRBMathUD60x18.mul(_ethPayAmount, _data.weight);
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _userTokenBalance);
        uint256 initTerminalBalance = address(__terminal).balance;

        // First dist should be fine based on price
        __terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: 1_800_000_000,
            currency: uint32(uint160(address(usdcToken()))),
            token: JBTokens.ETH, // unused
            minReturnedTokens: 0
        });

        uint256 _distributedAmount = PRBMath.mulDiv(
            1_800_000_000,
            10 ** 18, // Use _MAX_FIXED_POINT_FIDELITY to keep as much of the `_amount.value`'s fidelity as possible when converting.
            _prices.priceFor({
                projectId: 1,
                currency: uint32(uint160(address(usdcToken()))),
                base: _ethCurrency,
                decimals: 18
            })
        );

        // Make sure the remaining balance is correct.
        assertEq(
            address(__terminal).balance,
            initTerminalBalance
                - PRBMath.mulDiv(
                    _distributedAmount, JBConstants.MAX_FEE, JBConstants.MAX_FEE + __terminal.FEE()
                )
        );

        // Next dist should be fine based on price
        __terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: 1_700_000_000,
            currency: uint32(uint160(address(usdcToken()))),
            token: JBTokens.ETH, // unused
            minReturnedTokens: 0
        });
    }

    function testMultipleDistroLimitCurrencies() external {
        uint256 _ethPayAmount = 3 ether;
        vm.deal(_beneficiary, _ethPayAmount);
        vm.prank(_beneficiary);

        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](2);
        _distributionLimits[0] = JBCurrencyAmount({value: 1 ether, currency: _ethCurrency});
        _distributionLimits[1] = JBCurrencyAmount({
            value: 2000 * 10 ** 18,
            currency: uint32(uint160(address(usdcToken())))
        });
        _fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: address(__terminal),
            token: JBTokens.ETH,
            distributionLimits: _distributionLimits,
            overflowAllowances: new JBCurrencyAmount[](0)
        });

        JBFundingCycleConfig[] memory _cycleConfig = new JBFundingCycleConfig[](1);

        _cycleConfig[0].mustStartAtOrAfter = 0;
        _cycleConfig[0].data = _data;
        _cycleConfig[0].metadata = _metadata;
        _cycleConfig[0].groupedSplits = _groupedSplits;
        _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContexts = new JBAccountingContextConfig[](2);
        _accountingContexts[0] =
            JBAccountingContextConfig({token: JBTokens.ETH, standard: JBTokenStandards.NATIVE});
        _accountingContexts[1] = JBAccountingContextConfig({
            token: address(usdcToken()),
            standard: JBTokenStandards.ERC20
        });
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: __terminal, accountingContextConfigs: _accountingContexts});

        uint256 _projectId = _controller.launchProjectFor({
            owner: _projectOwner,
            projectMetadata: "myIPFSHash",
            fundingCycleConfigurations: _cycleConfig,
            terminalConfigurations: _terminalConfigurations,
            memo: ""
        });

        __terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokens.ETH, // unused
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "Take my money!",
            metadata: new bytes(0)
        });

        uint256 _price = 0.0005 * 10 ** 18; // 1/2000
        vm.startPrank(_projectOwner);
        MockPriceFeed _priceFeedEthUsd = new MockPriceFeed(_price, 18);
        vm.label(address(_priceFeedEthUsd), "MockPrice Feed MyToken-ETH");

        _prices.addFeedFor({
            projectId: _projectId,
            currency: _ethCurrency,
            base: uint32(uint160(address(usdcToken()))),
            priceFeed: _priceFeedEthUsd
        });

        // Make sure the beneficiary has a balance of JBTokens
        uint256 _userTokenBalance = PRBMathUD60x18.mul(_ethPayAmount, _data.weight);
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _userTokenBalance);

        uint256 initTerminalBalance = address(__terminal).balance;
        uint256 ownerBalanceBeforeFirst = _projectOwner.balance;

        __terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: 3_000_000_000,
            currency: uint32(uint160(address(usdcToken()))),
            token: JBTokens.ETH, // unused
            minReturnedTokens: 0
        });

        uint256 _distributedAmount = PRBMath.mulDiv(
            3_000_000_000,
            10 ** 18, // Use _MAX_FIXED_POINT_FIDELITY to keep as much of the `_amount.value`'s fidelity as possible when converting.
            _prices.priceFor({
                projectId: 1,
                currency: uint32(uint160(address(usdcToken()))),
                base: _ethCurrency,
                decimals: 18
            })
        );

        assertEq(
            _projectOwner.balance,
            ownerBalanceBeforeFirst
                + PRBMath.mulDiv(
                    _distributedAmount, JBConstants.MAX_FEE, JBConstants.MAX_FEE + __terminal.FEE()
                )
        );

        // Funds leaving the ecosystem -> fee taken
        assertEq(
            address(__terminal).balance,
            initTerminalBalance
                - PRBMath.mulDiv(
                    _distributedAmount, JBConstants.MAX_FEE, JBConstants.MAX_FEE + __terminal.FEE()
                )
        );

        uint256 _balanceBeforeEthDist = address(__terminal).balance;
        uint256 _ownerBalanceBeforeEthDist = _projectOwner.balance;

        __terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: 1 ether,
            currency: _ethCurrency,
            token: JBTokens.ETH, // unused
            minReturnedTokens: 0
        });

        // Funds leaving the ecosystem -> fee taken
        assertEq(
            _projectOwner.balance,
            _ownerBalanceBeforeEthDist
                + PRBMath.mulDiv(1 ether, JBConstants.MAX_FEE, JBConstants.MAX_FEE + __terminal.FEE())
        );

        assertEq(
            address(__terminal).balance,
            _balanceBeforeEthDist
                - PRBMath.mulDiv(1 ether, JBConstants.MAX_FEE, JBConstants.MAX_FEE + __terminal.FEE())
        );
    }
}
