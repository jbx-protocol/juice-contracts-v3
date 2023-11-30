// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";
import {MockPriceFeed} from "./mock/MockPriceFeed.sol";

/// Funds can be accessed in three ways:
/// 1. project owners set a payout limit to prioritize spending to pre-determined destinations. funds being removed from the protocol incurs fees.
/// 2. project owners set a surplus allowance to allow spending funds from the treasury in excess of the payout limit. incurs fees.
/// 3. token holders can redeem tokens to access funds in excess of the payout limit. incurs fees if the redemption rate != 100%.
/// Each of these incurs protocol fees if the project with ID #1 accepts the token being accessed.
contract TestAccessToFunds_Local is TestBaseWorkflow {
    uint256 private constant _FEE_PROJECT_ID = 1;
    uint8 private constant _WEIGHT_DECIMALS = 18; // FIXED
    uint8 private constant _ETH_DECIMALS = 18; // FIXED
    uint8 private constant _PRICE_FEED_DECIMALS = 10;
    uint256 private constant _USD_PRICE_PER_ETH = 2000 * 10 ** _PRICE_FEED_DECIMALS; // 2000 USDC == 1 ETH

    IJBController private _controller;
    IJBPrices private _prices;
    IJBMultiTerminal private _terminal;
    IJBMultiTerminal private _terminal2;
    IJBTokens private _tokens;
    address private _projectOwner;
    address private _beneficiary;
    MockERC20 private _usdcToken;
    uint256 private _projectId;

    JBRulesetData private _data;
    JBRulesetMetadata private _metadata;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _usdcToken = usdcToken();
        _tokens = jbTokens();
        _controller = jbController();
        _prices = jbPrices();
        _terminal = jbPayoutRedemptionTerminal();
        _terminal2 = jbPayoutRedemptionTerminal2();
        _data = JBRulesetData({
            duration: 0,
            weight: 1000 * 10 ** _WEIGHT_DECIMALS,
            decayRate: 0,
            approvalHook: IJBRulesetApprovalHook(address(0))
        });

        _metadata = JBRulesetMetadata({
            global: JBGlobalRulesetMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate: JBConstants.MAX_RESERVED_RATE / 2, //50%
            redemptionRate: JBConstants.MAX_REDEMPTION_RATE / 2, //50%
            baseCurrency: uint32(uint160(JBTokenList.ETH)),
            pausePay: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalSurplusForRedemptions: true,
            useDataHookForPay: false,
            useDataHookForRedeem: false,
            dataHook: address(0),
            metadata: 0
        });
    }

    // Tests that basic payout limit and surplus allowance limits work as intended.
    function testETHAllowance() public {
        // Hardcode values to use.
        uint256 _ethCurrencyPayoutLimit = 10 * 10 ** _ETH_DECIMALS;
        uint256 _ethCurrencySurplusAllowance = 5 * 10 ** _ETH_DECIMALS;

        // Package up the limits for the given terminal.
        JBFundAccessLimitGroup[] memory _fundAccessLimitGroup = new JBFundAccessLimitGroup[](1);
        {
            // Specify a payout limit.
            JBCurrencyAmount[] memory _payoutLimits = new JBCurrencyAmount[](1);
            _payoutLimits[0] = JBCurrencyAmount({
                amount: _ethCurrencyPayoutLimit,
                currency: uint32(uint160(JBTokenList.ETH))
            });

            // Specify a surplus allowance.
            JBCurrencyAmount[] memory _surplusAllowances = new JBCurrencyAmount[](1);
            _surplusAllowances[0] = JBCurrencyAmount({
                amount: _ethCurrencySurplusAllowance,
                currency: uint32(uint160(JBTokenList.ETH))
            });

            _fundAccessLimitGroup[0] = JBFundAccessLimitGroup({
                terminal: address(_terminal),
                token: JBTokenList.ETH,
                payoutLimits: _payoutLimits,
                surplusAllowances: _surplusAllowances
            });
        }

        {
            // Package up the configuration info.
            JBRulesetConfig[] memory _rulesetConfigurations = new JBRulesetConfig[](1);
            _rulesetConfigurations[0].mustStartAtOrAfter = 0;
            _rulesetConfigurations[0].data = _data;
            _rulesetConfigurations[0].metadata = _metadata;
            _rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
            _rulesetConfigurations[0].fundAccessLimitGroup = _fundAccessLimitGroup;

            JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
            JBAccountingContextConfig[] memory _accountingContextConfigs =
                new JBAccountingContextConfig[](1);
            _accountingContextConfigs[0] = JBAccountingContextConfig({
                token: JBTokenList.ETH,
                standard: JBTokenStandards.NATIVE
            });
            _terminalConfigurations[0] = JBTerminalConfig({
                terminal: _terminal,
                accountingContextConfigs: _accountingContextConfigs
            });

            // First project for fee collection
            _controller.launchProjectFor({
                owner: address(420), // random
                projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations, // set terminals where fees will be received
                memo: ""
            });

            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations,
                memo: ""
            });
        }

        // Get a reference to the amount being paid, such that the payout limit is met with two times the surplus than is allowed to be withdrawn.
        uint256 _ethPayAmount = _ethCurrencyPayoutLimit + (2 * _ethCurrencySurplusAllowance);

        // Pay the project such that the _beneficiary receives project tokens.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokenList.ETH,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(
            _ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS
        ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
            _ethPayAmount
        );

        // Use the full discretionary allowance of surplus.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethCurrencySurplusAllowance,
            currency: uint32(uint160(JBTokenList.ETH)),
            token: JBTokenList.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            memo: "MEMO"
        });

        // Make sure the beneficiary received the funds and that they are no longer in the terminal.
        uint256 _beneficiaryEthBalance = PRBMath.mulDiv(
            _ethCurrencySurplusAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.FEE()
        );
        assertEq(_beneficiary.balance, _beneficiaryEthBalance);
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
            _ethPayAmount - _ethCurrencySurplusAllowance
        );

        // Make sure the fee was paid correctly.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH),
            _ethCurrencySurplusAllowance - _beneficiaryEthBalance
        );
        assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

        // Make sure the project owner got the expected number of tokens.
        assertEq(
            _tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID),
            PRBMath.mulDiv(
                _ethCurrencySurplusAllowance - _beneficiaryEthBalance,
                _data.weight,
                10 ** _ETH_DECIMALS
            ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE
        );

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.sendPayoutsOf({
            projectId: _projectId,
            amount: _ethCurrencyPayoutLimit,
            currency: uint32(uint160(JBTokenList.ETH)),
            token: JBTokenList.ETH,
            minReturnedTokens: 0
        });

        // Make sure the project owner received the distributed funds.
        uint256 _projectOwnerEthBalance = (_ethCurrencyPayoutLimit * JBConstants.MAX_FEE)
            / (_terminal.FEE() + JBConstants.MAX_FEE);

        // Make sure the project owner received the full amount.
        assertEq(_projectOwner.balance, _projectOwnerEthBalance);

        // Make sure the fee was paid correctly.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH),
            (_ethCurrencySurplusAllowance - _beneficiaryEthBalance)
                + (_ethCurrencyPayoutLimit - _projectOwnerEthBalance)
        );
        assertEq(
            address(_terminal).balance,
            _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
        );

        // Make sure the project owner got the expected number of tokens.
        assertEq(
            _tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID),
            PRBMath.mulDiv(
                (_ethCurrencySurplusAllowance - _beneficiaryEthBalance)
                    + (_ethCurrencyPayoutLimit - _projectOwnerEthBalance),
                _data.weight,
                10 ** _ETH_DECIMALS
            ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE
        );

        // Redeem ETH from the surplus using all of the _beneficiary's tokens.
        vm.prank(_beneficiary);
        _terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            token: JBTokenList.ETH,
            count: _beneficiaryTokenBalance,
            minReclaimed: 0,
            beneficiary: payable(_beneficiary),
            metadata: new bytes(0)
        });

        // Make sure the beneficiary doesn't have tokens left.
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), 0);

        // Get the expected amount reclaimed.
        uint256 _ethReclaimAmount = PRBMath.mulDiv(
            PRBMath.mulDiv(
                _ethPayAmount - _ethCurrencySurplusAllowance - _ethCurrencyPayoutLimit,
                _beneficiaryTokenBalance,
                PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
            ),
            _metadata.redemptionRate
                + PRBMath.mulDiv(
                    _beneficiaryTokenBalance,
                    JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                    PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
                ),
            JBConstants.MAX_REDEMPTION_RATE
        );

        // Calculate the fee from the redemption.
        uint256 _feeAmount = _ethReclaimAmount
            - _ethReclaimAmount * JBConstants.MAX_FEE / (_terminal.FEE() + JBConstants.MAX_FEE);
        assertEq(_beneficiary.balance, _beneficiaryEthBalance + _ethReclaimAmount - _feeAmount);

        // // Make sure the fee was paid correctly.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH),
            (_ethCurrencySurplusAllowance - _beneficiaryEthBalance)
                + (_ethCurrencyPayoutLimit - _projectOwnerEthBalance) + _feeAmount
        );
        assertEq(
            address(_terminal).balance,
            _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
                - (_ethReclaimAmount - _feeAmount)
        );

        // Make sure the project owner got the expected number of tokens from the fee.
        assertEq(
            _tokens.totalBalanceOf(_beneficiary, _FEE_PROJECT_ID),
            PRBMath.mulDiv(_feeAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate
                / JBConstants.MAX_RESERVED_RATE
        );
    }

    function testFuzzETHAllowance(
        uint224 _ethCurrencySurplusAllowance,
        uint224 _ethCurrencyPayoutLimit,
        uint256 _ethPayAmount
    ) public {
        // Make sure the amount of eth to pay is bounded.
        _ethPayAmount = bound(_ethPayAmount, 0, 1_000_000 * 10 ** _ETH_DECIMALS);

        // Make sure the values don't surplus the registry.
        unchecked {
            vm.assume(
                _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit
                    >= _ethCurrencySurplusAllowance
                    && _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit >= _ethCurrencyPayoutLimit
            );
        }

        // Package up the limits for the given terminal.
        JBFundAccessLimitGroup[] memory _fundAccessLimitGroup = new JBFundAccessLimitGroup[](1);
        {
            // Specify a payout limit.
            JBCurrencyAmount[] memory _payoutLimits = new JBCurrencyAmount[](1);
            _payoutLimits[0] = JBCurrencyAmount({
                amount: _ethCurrencyPayoutLimit,
                currency: uint32(uint160(JBTokenList.ETH))
            });

            // Specify a surplus allowance.
            JBCurrencyAmount[] memory _surplusAllowances = new JBCurrencyAmount[](1);
            _surplusAllowances[0] = JBCurrencyAmount({
                amount: _ethCurrencySurplusAllowance,
                currency: uint32(uint160(JBTokenList.ETH))
            });

            _fundAccessLimitGroup[0] = JBFundAccessLimitGroup({
                terminal: address(_terminal),
                token: JBTokenList.ETH,
                payoutLimits: _payoutLimits,
                surplusAllowances: _surplusAllowances
            });
        }

        {
            // Package up the configuration info.
            JBRulesetConfig[] memory _rulesetConfigurations = new JBRulesetConfig[](1);
            _rulesetConfigurations[0].mustStartAtOrAfter = 0;
            _rulesetConfigurations[0].data = _data;
            _rulesetConfigurations[0].metadata = _metadata;
            _rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
            _rulesetConfigurations[0].fundAccessLimitGroup = _fundAccessLimitGroup;

            JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
            JBAccountingContextConfig[] memory _accountingContextConfigs =
                new JBAccountingContextConfig[](1);
            _accountingContextConfigs[0] = JBAccountingContextConfig({
                token: JBTokenList.ETH,
                standard: JBTokenStandards.NATIVE
            });
            _terminalConfigurations[0] = JBTerminalConfig({
                terminal: _terminal,
                accountingContextConfigs: _accountingContextConfigs
            });

            // First project for fee collection
            _controller.launchProjectFor({
                owner: address(420), // random
                projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
                rulesetConfigurations: _rulesetConfigurations, // use the same ruleset configs
                terminalConfigurations: _terminalConfigurations, // set terminals where fees will be received
                memo: ""
            });

            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations,
                memo: ""
            });
        }

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokenList.ETH,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(
            _ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS
        ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
            _ethPayAmount
        );

        // Revert if there's no allowance.
        if (_ethCurrencySurplusAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
            // Revert if there's no surplus, or if too much is being withdrawn.
        } else if (_ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary allowance of surplus.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethCurrencySurplusAllowance,
            currency: uint32(uint160(JBTokenList.ETH)),
            token: JBTokenList.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's balance;
        uint256 _beneficiaryEthBalance;

        // Check the collected balance if one is expected.
        if (_ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance = PRBMath.mulDiv(
                _ethCurrencySurplusAllowance,
                JBConstants.MAX_FEE,
                JBConstants.MAX_FEE + _terminal.FEE()
            );
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _ethCurrencySurplusAllowance
            );

            // Make sure the fee was paid correctly.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH),
                _ethCurrencySurplusAllowance - _beneficiaryEthBalance
            );
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(
                _tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID),
                PRBMath.mulDiv(
                    _ethCurrencySurplusAllowance - _beneficiaryEthBalance,
                    _data.weight,
                    10 ** _ETH_DECIMALS
                ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE
            );
        } else {
            // Set the eth surplus allowance value to 0 if it wasnt used.
            _ethCurrencySurplusAllowance = 0;
        }

        // Revert if the payout limit is greater than the balance.
        if (_ethCurrencyPayoutLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));

            // Revert if there's no payout limit.
        } else if (_ethCurrencyPayoutLimit == 0) {
            vm.expectRevert(abi.encodeWithSignature("PAYOUT_LIMIT_EXCEEDED()"));
        }

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.sendPayoutsOf({
            projectId: _projectId,
            amount: _ethCurrencyPayoutLimit,
            currency: uint32(uint160(JBTokenList.ETH)),
            token: JBTokenList.ETH,
            minReturnedTokens: 0
        });

        uint256 _projectOwnerEthBalance;

        // Check the collected distribution if one is expected.
        if (_ethCurrencyPayoutLimit <= _ethPayAmount && _ethCurrencyPayoutLimit != 0) {
            // Make sure the project owner received the distributed funds.
            _projectOwnerEthBalance = (_ethCurrencyPayoutLimit * JBConstants.MAX_FEE)
                / (_terminal.FEE() + JBConstants.MAX_FEE);
            assertEq(_projectOwner.balance, _projectOwnerEthBalance);
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _ethCurrencySurplusAllowance - _ethCurrencyPayoutLimit
            );

            // Make sure the fee was paid correctly.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH),
                (_ethCurrencySurplusAllowance - _beneficiaryEthBalance)
                    + (_ethCurrencyPayoutLimit - _projectOwnerEthBalance)
            );
            assertEq(
                address(_terminal).balance,
                _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
            );

            // Make sure the project owner got the expected number of tokens.
            assertEq(
                _tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID),
                PRBMath.mulDiv(
                    (_ethCurrencySurplusAllowance - _beneficiaryEthBalance)
                        + (_ethCurrencyPayoutLimit - _projectOwnerEthBalance),
                    _data.weight,
                    10 ** _ETH_DECIMALS
                ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE
            );
        }

        // Redeem ETH from the surplus using all of the _beneficiary's tokens.
        vm.prank(_beneficiary);
        _terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            count: _beneficiaryTokenBalance,
            token: JBTokenList.ETH,
            minReclaimed: 0,
            beneficiary: payable(_beneficiary),
            metadata: new bytes(0)
        });

        // Make sure the beneficiary doesn't have tokens left.
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), 0);

        // Check for a new beneficiary balance if one is expected.
        if (_ethPayAmount > _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit) {
            // Get the expected amount reclaimed.
            uint256 _ethReclaimAmount = PRBMath.mulDiv(
                PRBMath.mulDiv(
                    _ethPayAmount - _ethCurrencySurplusAllowance - _ethCurrencyPayoutLimit,
                    _beneficiaryTokenBalance,
                    PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
                ),
                _metadata.redemptionRate
                    + PRBMath.mulDiv(
                        _beneficiaryTokenBalance,
                        JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                        PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
                    ),
                JBConstants.MAX_REDEMPTION_RATE
            );
            // Calculate the fee from the redemption.
            uint256 _feeAmount = _ethReclaimAmount
                - _ethReclaimAmount * JBConstants.MAX_FEE / (_terminal.FEE() + JBConstants.MAX_FEE);
            assertEq(_beneficiary.balance, _beneficiaryEthBalance + _ethReclaimAmount - _feeAmount);

            // Make sure the fee was paid correctly.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH),
                (_ethCurrencySurplusAllowance - _beneficiaryEthBalance)
                    + (_ethCurrencyPayoutLimit - _projectOwnerEthBalance) + _feeAmount
            );
            assertEq(
                address(_terminal).balance,
                _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
                    - (_ethReclaimAmount - _feeAmount)
            );

            // Make sure the project owner got the expected number of tokens from the fee.
            assertEq(
                _tokens.totalBalanceOf(_beneficiary, _FEE_PROJECT_ID),
                PRBMath.mulDiv(_feeAmount, _data.weight, 10 ** _ETH_DECIMALS)
                    * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE
            );
        }
    }

    function testFuzzETHAllowanceWithRevertingFeeProject(
        uint224 _ethCurrencySurplusAllowance,
        uint224 _ethCurrencyPayoutLimit,
        uint256 _ethPayAmount,
        bool _feeProjectAcceptsToken
    ) public {
        // Make sure the amount of eth to pay is bounded.
        _ethPayAmount = bound(_ethPayAmount, 0, 1_000_000 * 10 ** _ETH_DECIMALS);

        // Make sure the values don't surplus the registry.
        unchecked {
            vm.assume(
                _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit
                    >= _ethCurrencySurplusAllowance
                    && _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit >= _ethCurrencyPayoutLimit
            );
        }

        // Package up the limits for the given terminal.
        JBFundAccessLimitGroup[] memory _fundAccessLimitGroup = new JBFundAccessLimitGroup[](1);
        {
            // Specify a payout limit.
            JBCurrencyAmount[] memory _payoutLimits = new JBCurrencyAmount[](1);
            _payoutLimits[0] = JBCurrencyAmount({
                amount: _ethCurrencyPayoutLimit,
                currency: uint32(uint160(JBTokenList.ETH))
            });

            // Specify a surplus allowance.
            JBCurrencyAmount[] memory _surplusAllowances = new JBCurrencyAmount[](1);
            _surplusAllowances[0] = JBCurrencyAmount({
                amount: _ethCurrencySurplusAllowance,
                currency: uint32(uint160(JBTokenList.ETH))
            });

            _fundAccessLimitGroup[0] = JBFundAccessLimitGroup({
                terminal: address(_terminal),
                token: JBTokenList.ETH,
                payoutLimits: _payoutLimits,
                surplusAllowances: _surplusAllowances
            });
        }

        {
            JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
            JBAccountingContextConfig[] memory _accountingContextConfigs =
                new JBAccountingContextConfig[](1);
            _accountingContextConfigs[0] = JBAccountingContextConfig({
                token: JBTokenList.ETH,
                standard: JBTokenStandards.NATIVE
            });

            _terminalConfigurations[0] = JBTerminalConfig({
                terminal: _terminal,
                accountingContextConfigs: _accountingContextConfigs
            });

            // First project for fee collection
            _controller.launchProjectFor({
                owner: address(420), // random
                projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
                rulesetConfigurations: new JBRulesetConfig[](0), // No ruleset config will force revert when paid.
                // Set the fee collecting terminal's ETH accounting context if the test calls for doing so.
                terminalConfigurations: _feeProjectAcceptsToken
                    ? _terminalConfigurations
                    : new JBTerminalConfig[](0), // set terminals where fees will be received
                memo: ""
            });

            // Package up the configuration info.
            JBRulesetConfig[] memory _rulesetConfigurations = new JBRulesetConfig[](1);
            _rulesetConfigurations[0].mustStartAtOrAfter = 0;
            _rulesetConfigurations[0].data = _data;
            _rulesetConfigurations[0].metadata = _metadata;
            _rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
            _rulesetConfigurations[0].fundAccessLimitGroup = _fundAccessLimitGroup;

            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations,
                memo: ""
            });
        }

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokenList.ETH,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(
            _ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS
        ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
            _ethPayAmount
        );

        // Revert if there's no allowance.
        if (_ethCurrencySurplusAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
            // Revert if there's no surplus, or if too much is being withdrawn.
        } else if (_ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary allowance of surplus.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethCurrencySurplusAllowance,
            currency: uint32(uint160(JBTokenList.ETH)),
            token: JBTokenList.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's balance;
        uint256 _beneficiaryEthBalance;

        // Check the collected balance if one is expected.
        if (_ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance = PRBMath.mulDiv(
                _ethCurrencySurplusAllowance,
                JBConstants.MAX_FEE,
                JBConstants.MAX_FEE + _terminal.FEE()
            );
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            // Make sure the fee stays in the treasury.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _beneficiaryEthBalance
            );

            // Make sure the fee was not taken.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH), 0
            );
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got no tokens.
            assertEq(_tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID), 0);
        } else {
            // Set the eth surplus allowance value to 0 if it wasnt used.
            _ethCurrencySurplusAllowance = 0;
        }

        // Revert if the payout limit is greater than the balance.
        if (_ethCurrencyPayoutLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));

            // Revert if there's no payout limit.
        } else if (_ethCurrencyPayoutLimit == 0) {
            vm.expectRevert(abi.encodeWithSignature("PAYOUT_LIMIT_EXCEEDED()"));
        }

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.sendPayoutsOf({
            projectId: _projectId,
            amount: _ethCurrencyPayoutLimit,
            currency: uint32(uint160(JBTokenList.ETH)),
            token: JBTokenList.ETH,
            minReturnedTokens: 0
        });

        uint256 _projectOwnerEthBalance;

        // Check the collected distribution if one is expected.
        if (_ethCurrencyPayoutLimit <= _ethPayAmount && _ethCurrencyPayoutLimit != 0) {
            // Make sure the project owner received the distributed funds.
            _projectOwnerEthBalance = (_ethCurrencyPayoutLimit * JBConstants.MAX_FEE)
                / (_terminal.FEE() + JBConstants.MAX_FEE);
            assertEq(_projectOwner.balance, _projectOwnerEthBalance);
            // Make sure the fee stays in the treasury.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
            );

            // Make sure the fee was paid correctly.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH), 0
            );
            assertEq(
                address(_terminal).balance,
                _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
            );

            // Make sure the project owner got the expected number of tokens.
            assertEq(_tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID), 0);
        }

        // Redeem ETH from the surplus using all of the _beneficiary's tokens.
        vm.prank(_beneficiary);
        _terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            count: _beneficiaryTokenBalance,
            token: JBTokenList.ETH,
            minReclaimed: 0,
            beneficiary: payable(_beneficiary),
            metadata: new bytes(0)
        });

        // Make sure the beneficiary doesn't have tokens left.
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), 0);

        // Check for a new beneficiary balance if one is expected.
        if (_ethPayAmount > _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit) {
            // Get the expected amount reclaimed.
            uint256 _ethReclaimAmount = PRBMath.mulDiv(
                PRBMath.mulDiv(
                    _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance,
                    _beneficiaryTokenBalance,
                    PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
                ),
                _metadata.redemptionRate
                    + PRBMath.mulDiv(
                        _beneficiaryTokenBalance,
                        JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                        PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
                    ),
                JBConstants.MAX_REDEMPTION_RATE
            );

            // Calculate the fee from the redemption.
            uint256 _feeAmount = _ethReclaimAmount
                - _ethReclaimAmount * JBConstants.MAX_FEE / (_terminal.FEE() + JBConstants.MAX_FEE);
            assertEq(_beneficiary.balance, _beneficiaryEthBalance + _ethReclaimAmount - _feeAmount);
            // Make sure the fee stays in the treasury.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
                    - (_ethReclaimAmount - _feeAmount)
            );

            // Make sure the fee was paid correctly.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH), 0
            );
            assertEq(
                address(_terminal).balance,
                _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
                    - (_ethReclaimAmount - _feeAmount)
            );

            // Make sure the project owner got the expected number of tokens from the fee.
            assertEq(_tokens.totalBalanceOf(_beneficiary, _FEE_PROJECT_ID), 0);
        }
    }

    function testFuzzETHAllowanceForTheFeeProject(
        uint224 _ethCurrencySurplusAllowance,
        uint224 _ethCurrencyPayoutLimit,
        uint256 _ethPayAmount
    ) public {
        // Make sure the amount of eth to pay is bounded.
        _ethPayAmount = bound(_ethPayAmount, 0, 1_000_000 * 10 ** _ETH_DECIMALS);

        // Make sure the values don't surplus the registry.
        unchecked {
            vm.assume(
                _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit
                    >= _ethCurrencySurplusAllowance
                    && _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit >= _ethCurrencyPayoutLimit
            );
        }

        // Package up the limits for the given terminal.
        JBFundAccessLimitGroup[] memory _fundAccessLimitGroup = new JBFundAccessLimitGroup[](1);
        {
            // Specify a payout limit.
            JBCurrencyAmount[] memory _payoutLimits = new JBCurrencyAmount[](1);
            _payoutLimits[0] = JBCurrencyAmount({
                amount: _ethCurrencyPayoutLimit,
                currency: uint32(uint160(JBTokenList.ETH))
            });

            // Specify a surplus allowance.
            JBCurrencyAmount[] memory _surplusAllowances = new JBCurrencyAmount[](1);
            _surplusAllowances[0] = JBCurrencyAmount({
                amount: _ethCurrencySurplusAllowance,
                currency: uint32(uint160(JBTokenList.ETH))
            });

            _fundAccessLimitGroup[0] = JBFundAccessLimitGroup({
                terminal: address(_terminal),
                token: JBTokenList.ETH,
                payoutLimits: _payoutLimits,
                surplusAllowances: _surplusAllowances
            });
        }

        {
            // Package up the configuration info.
            JBRulesetConfig[] memory _rulesetConfigurations = new JBRulesetConfig[](1);
            _rulesetConfigurations[0].mustStartAtOrAfter = 0;
            _rulesetConfigurations[0].data = _data;
            _rulesetConfigurations[0].metadata = _metadata;
            _rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
            _rulesetConfigurations[0].fundAccessLimitGroup = _fundAccessLimitGroup;

            JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
            JBAccountingContextConfig[] memory _accountingContextConfigs =
                new JBAccountingContextConfig[](1);
            _accountingContextConfigs[0] = JBAccountingContextConfig({
                token: JBTokenList.ETH,
                standard: JBTokenStandards.NATIVE
            });

            _terminalConfigurations[0] = JBTerminalConfig({
                terminal: _terminal,
                accountingContextConfigs: _accountingContextConfigs
            });

            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations,
                memo: ""
            });
        }

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokenList.ETH,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(
            _ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS
        ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
            _ethPayAmount
        );

        // Revert if there's no allowance.
        if (_ethCurrencySurplusAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
            // Revert if there's no surplus, or if too much is being withdrawn.
        } else if (_ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary allowance of surplus.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethCurrencySurplusAllowance,
            currency: uint32(uint160(JBTokenList.ETH)),
            token: JBTokenList.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's balance;
        uint256 _beneficiaryEthBalance;

        // Check the collected balance if one is expected.
        if (_ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance = PRBMath.mulDiv(
                _ethCurrencySurplusAllowance,
                JBConstants.MAX_FEE,
                JBConstants.MAX_FEE + _terminal.FEE()
            );
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _beneficiaryEthBalance
            );
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(
                _tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID),
                PRBMath.mulDiv(
                    _ethCurrencySurplusAllowance - _beneficiaryEthBalance,
                    _data.weight,
                    10 ** _ETH_DECIMALS
                ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE
            );
        } else {
            // Set the eth surplus allowance value to 0 if it wasnt used.
            _ethCurrencySurplusAllowance = 0;
        }

        // Revert if the payout limit is greater than the balance.
        if (_ethCurrencyPayoutLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));

            // Revert if there's no payout limit.
        } else if (_ethCurrencyPayoutLimit == 0) {
            vm.expectRevert(abi.encodeWithSignature("PAYOUT_LIMIT_EXCEEDED()"));
        }

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.sendPayoutsOf({
            projectId: _projectId,
            amount: _ethCurrencyPayoutLimit,
            currency: uint32(uint160(JBTokenList.ETH)),
            token: JBTokenList.ETH,
            minReturnedTokens: 0
        });

        uint256 _projectOwnerEthBalance;

        // Check the collected distribution if one is expected.
        if (_ethCurrencyPayoutLimit <= _ethPayAmount && _ethCurrencyPayoutLimit != 0) {
            // Make sure the project owner received the distributed funds.
            _projectOwnerEthBalance = (_ethCurrencyPayoutLimit * JBConstants.MAX_FEE)
                / (_terminal.FEE() + JBConstants.MAX_FEE);
            assertEq(_projectOwner.balance, _projectOwnerEthBalance);
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
            );
            assertEq(
                address(_terminal).balance,
                _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
            );

            // Make sure the project owner got the expected number of tokens.
            assertEq(
                _tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID),
                PRBMath.mulDiv(
                    (_ethCurrencySurplusAllowance - _beneficiaryEthBalance)
                        + (_ethCurrencyPayoutLimit - _projectOwnerEthBalance),
                    _data.weight,
                    10 ** _ETH_DECIMALS
                ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE
            );
        }

        // Redeem ETH from the surplus using all of the _beneficiary's tokens.
        vm.prank(_beneficiary);
        _terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            count: _beneficiaryTokenBalance,
            token: JBTokenList.ETH,
            minReclaimed: 0,
            beneficiary: payable(_beneficiary),
            metadata: new bytes(0)
        });

        // Check for a new beneficiary balance if one is expected.
        if (_ethPayAmount > _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit) {
            // Keep a reference to the total amount paid, including from fees.
            uint256 _totalPaid = _ethPayAmount
                + (_ethCurrencySurplusAllowance - _beneficiaryEthBalance)
                + (_ethCurrencyPayoutLimit - _projectOwnerEthBalance);

            // Get the expected amount reclaimed.
            uint256 _ethReclaimAmount = PRBMath.mulDiv(
                PRBMath.mulDiv(
                    _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance,
                    _beneficiaryTokenBalance,
                    PRBMath.mulDiv(_totalPaid, _data.weight, 10 ** _ETH_DECIMALS)
                ),
                _metadata.redemptionRate
                    + PRBMath.mulDiv(
                        _beneficiaryTokenBalance,
                        JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                        PRBMath.mulDiv(_totalPaid, _data.weight, 10 ** _ETH_DECIMALS)
                    ),
                JBConstants.MAX_REDEMPTION_RATE
            );
            // Calculate the fee from the redemption.
            uint256 _feeAmount = _ethReclaimAmount
                - _ethReclaimAmount * JBConstants.MAX_FEE / (_terminal.FEE() + JBConstants.MAX_FEE);

            // Make sure the beneficiary has token from the fee just paid.
            assertEq(
                _tokens.totalBalanceOf(_beneficiary, _projectId),
                PRBMath.mulDiv(_feeAmount, _data.weight, 10 ** _ETH_DECIMALS)
                    * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE
            );

            // Make sure the beneficiary received the funds.
            assertEq(_beneficiary.balance, _beneficiaryEthBalance + _ethReclaimAmount - _feeAmount);

            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
                    - (_ethReclaimAmount - _feeAmount)
            );
            assertEq(
                address(_terminal).balance,
                _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
                    - (_ethReclaimAmount - _feeAmount)
            );
        }
    }

    function testFuzzMultiCurrencyAllowance(
        uint224 _ethCurrencySurplusAllowance,
        uint224 _ethCurrencyPayoutLimit,
        uint256 _ethPayAmount,
        uint224 _usdCurrencySurplusAllowance,
        uint224 _usdCurrencyPayoutLimit,
        uint256 _usdcPayAmount
    ) public {
        // Make sure the amount of eth to pay is bounded.
        _ethPayAmount = bound(_ethPayAmount, 0, 1_000_000 * 10 ** _ETH_DECIMALS);
        _usdcPayAmount = bound(_usdcPayAmount, 0, 1_000_000 * 10 ** _usdcToken.decimals());

        // Make sure the values don't surplus the registry.
        unchecked {
            // vm.assume(_ethCurrencySurplusAllowance + _cumulativePayoutLimit  >= _ethCurrencySurplusAllowance && _ethCurrencySurplusAllowance + _cumulativePayoutLimit >= _cumulativePayoutLimit);
            // vm.assume(_usdCurrencySurplusAllowance + (_usdCurrencyPayoutLimit + PRBMath.mulDiv(_ethCurrencyPayoutLimit, _USD_PRICE_PER_ETH, 10**_PRICE_FEED_DECIMALS))*2 >= _usdCurrencySurplusAllowance && _usdCurrencySurplusAllowance + _usdCurrencyPayoutLimit >= _usdCurrencyPayoutLimit);
            vm.assume(
                _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit
                    >= _ethCurrencySurplusAllowance
                    && _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit >= _ethCurrencyPayoutLimit
            );
            vm.assume(
                _usdCurrencySurplusAllowance + _usdCurrencyPayoutLimit
                    >= _usdCurrencySurplusAllowance
                    && _usdCurrencySurplusAllowance + _usdCurrencyPayoutLimit >= _usdCurrencyPayoutLimit
            );
        }

        {
            // Package up the limits for the given terminal.
            JBFundAccessLimitGroup[] memory _fundAccessLimitGroup = new JBFundAccessLimitGroup[](1);

            // Specify a payout limit.
            JBCurrencyAmount[] memory _payoutLimits = new JBCurrencyAmount[](2);
            _payoutLimits[0] = JBCurrencyAmount({
                amount: _ethCurrencyPayoutLimit,
                currency: uint32(uint160(JBTokenList.ETH))
            });
            _payoutLimits[1] = JBCurrencyAmount({
                amount: _usdCurrencyPayoutLimit,
                currency: uint32(uint160(address(_usdcToken)))
            });

            // Specify a surplus allowance.
            JBCurrencyAmount[] memory _surplusAllowances = new JBCurrencyAmount[](2);
            _surplusAllowances[0] = JBCurrencyAmount({
                amount: _ethCurrencySurplusAllowance,
                currency: uint32(uint160(JBTokenList.ETH))
            });
            _surplusAllowances[1] = JBCurrencyAmount({
                amount: _usdCurrencySurplusAllowance,
                currency: uint32(uint160(address(_usdcToken)))
            });

            _fundAccessLimitGroup[0] = JBFundAccessLimitGroup({
                terminal: address(_terminal),
                token: JBTokenList.ETH,
                payoutLimits: _payoutLimits,
                surplusAllowances: _surplusAllowances
            });

            // Package up the configuration info.
            JBRulesetConfig[] memory _rulesetConfigurations = new JBRulesetConfig[](1);
            _rulesetConfigurations[0].mustStartAtOrAfter = 0;
            _rulesetConfigurations[0].data = _data;
            _rulesetConfigurations[0].metadata = _metadata;
            _rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
            _rulesetConfigurations[0].fundAccessLimitGroup = _fundAccessLimitGroup;

            JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
            JBAccountingContextConfig[] memory _accountingContextConfigs =
                new JBAccountingContextConfig[](2);
            _accountingContextConfigs[0] = JBAccountingContextConfig({
                token: JBTokenList.ETH,
                standard: JBTokenStandards.NATIVE
            });
            _accountingContextConfigs[1] = JBAccountingContextConfig({
                token: address(_usdcToken),
                standard: JBTokenStandards.ERC20
            });

            _terminalConfigurations[0] = JBTerminalConfig({
                terminal: _terminal,
                accountingContextConfigs: _accountingContextConfigs
            });

            // First project for fee collection
            _controller.launchProjectFor({
                owner: address(420), // random
                projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
                rulesetConfigurations: _rulesetConfigurations, // use the same ruleset configs
                terminalConfigurations: _terminalConfigurations, // set terminals where fees will be received
                memo: ""
            });

            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations,
                memo: ""
            });
        }

        // Add a price feed to convert from ETH to USD currencies.
        {
            vm.startPrank(_projectOwner);
            MockPriceFeed _priceFeedEthUsd =
                new MockPriceFeed(_USD_PRICE_PER_ETH, _PRICE_FEED_DECIMALS);
            vm.label(address(_priceFeedEthUsd), "MockPrice Feed ETH-USDC");

            _prices.addPriceFeedFor({
                projectId: 0,
                pricingCurrency: uint32(uint160(address(_usdcToken))),
                unitCurrency: uint32(uint160(JBTokenList.ETH)),
                priceFeed: _priceFeedEthUsd
            });

            vm.stopPrank();
        }

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokenList.ETH,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens from the ETH payment.
        uint256 _beneficiaryTokenBalance =
            _unreservedPortion(PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS));
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);
        // Deal usdc to this contract.
        _usdcToken.mint(address(this), _usdcPayAmount);

        // Allow the terminal to spend the usdc.
        _usdcToken.approve(address(_terminal), _usdcPayAmount);

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay({
            projectId: _projectId,
            amount: _usdcPayAmount,
            token: address(_usdcToken),
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the terminal holds the full ETH balance.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
            _ethPayAmount
        );
        // Make sure the usdc is accounted for.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, address(_usdcToken)),
            _usdcPayAmount
        );
        assertEq(_usdcToken.balanceOf(address(_terminal)), _usdcPayAmount);

        {
            // Convert the usd amount to an eth amount, byway of the current weight used for issuance.
            uint256 _usdWeightedPayAmountConvertedToEth = PRBMath.mulDiv(
                _usdcPayAmount,
                _data.weight,
                PRBMath.mulDiv(
                    _USD_PRICE_PER_ETH, 10 ** _usdcToken.decimals(), 10 ** _PRICE_FEED_DECIMALS
                )
            );

            // Make sure the beneficiary got the expected number of tokens from the USDC payment.
            _beneficiaryTokenBalance += _unreservedPortion(_usdWeightedPayAmountConvertedToEth);
            assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);
        }

        // Revert if there's no ETH allowance.
        if (_ethCurrencySurplusAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        } else if (
            _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit + _toEth(_usdCurrencyPayoutLimit)
                > _ethPayAmount
        ) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary ETH allowance of surplus.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethCurrencySurplusAllowance,
            currency: uint32(uint160(JBTokenList.ETH)),
            token: JBTokenList.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's ETH balance;
        uint256 _beneficiaryEthBalance;

        // Check the collected balance if one is expected.
        if (
            _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit + _toEth(_usdCurrencyPayoutLimit)
                <= _ethPayAmount
        ) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance = PRBMath.mulDiv(
                _ethCurrencySurplusAllowance,
                JBConstants.MAX_FEE,
                JBConstants.MAX_FEE + _terminal.FEE()
            );
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _ethCurrencySurplusAllowance
            );

            // Make sure the fee was paid correctly.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH),
                _ethCurrencySurplusAllowance - _beneficiaryEthBalance
            );
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(
                _tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID),
                _unreservedPortion(
                    PRBMath.mulDiv(
                        _ethCurrencySurplusAllowance - _beneficiaryEthBalance,
                        _data.weight,
                        10 ** _ETH_DECIMALS
                    )
                )
            );
        } else {
            // Set the eth surplus allowance value to 0 if it wasnt used.
            _ethCurrencySurplusAllowance = 0;
        }

        // Revert if there's no ETH allowance.
        if (_usdCurrencySurplusAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
            // revert if the usd surplus allowance resolved to eth is greater than 0, and there is sufficient surplus to pull from including what was already pulled from.
        } else if (
            _toEth(_usdCurrencySurplusAllowance) > 0
                && _toEth(_usdCurrencySurplusAllowance + _usdCurrencyPayoutLimit)
                    + _ethCurrencyPayoutLimit + _ethCurrencySurplusAllowance > _ethPayAmount
        ) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary ETH allowance of surplus.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _usdCurrencySurplusAllowance,
            currency: uint32(uint160(address(_usdcToken))),
            token: JBTokenList.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            memo: "MEMO"
        });

        // Check the collected balance if one is expected.
        if (
            _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit
                + _toEth(_usdCurrencySurplusAllowance + _usdCurrencyPayoutLimit) <= _ethPayAmount
        ) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance += PRBMath.mulDiv(
                _toEth(_usdCurrencySurplusAllowance),
                JBConstants.MAX_FEE,
                JBConstants.MAX_FEE + _terminal.FEE()
            );
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _ethCurrencySurplusAllowance - _toEth(_usdCurrencySurplusAllowance)
            );

            // Make sure the fee was paid correctly.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH),
                _ethCurrencySurplusAllowance + _toEth(_usdCurrencySurplusAllowance)
                    - _beneficiaryEthBalance
            );
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(
                _tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID),
                _unreservedPortion(
                    PRBMath.mulDiv(
                        _ethCurrencySurplusAllowance + _toEth(_usdCurrencySurplusAllowance)
                            - _beneficiaryEthBalance,
                        _data.weight,
                        10 ** _ETH_DECIMALS
                    )
                )
            );
        } else {
            // Set the eth surplus allowance value to 0 if it wasnt used.
            _usdCurrencySurplusAllowance = 0;
        }

        // Payout limits
        {
            // Revert if the payout limit is greater than the balance.
            if (_ethCurrencyPayoutLimit > _ethPayAmount) {
                vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
                // Revert if there's no payout limit.
            } else if (_ethCurrencyPayoutLimit == 0) {
                vm.expectRevert(abi.encodeWithSignature("PAYOUT_LIMIT_EXCEEDED()"));
            }

            // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
            _terminal.sendPayoutsOf({
                projectId: _projectId,
                amount: _ethCurrencyPayoutLimit,
                currency: uint32(uint160(JBTokenList.ETH)),
                token: JBTokenList.ETH,
                minReturnedTokens: 0
            });

            uint256 _projectOwnerEthBalance;

            // Check the collected distribution if one is expected.
            if (_ethCurrencyPayoutLimit <= _ethPayAmount && _ethCurrencyPayoutLimit != 0) {
                // Make sure the project owner received the distributed funds.
                _projectOwnerEthBalance = (_ethCurrencyPayoutLimit * JBConstants.MAX_FEE)
                    / (_terminal.FEE() + JBConstants.MAX_FEE);
                assertEq(_projectOwner.balance, _projectOwnerEthBalance);
                assertEq(
                    jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                    _ethPayAmount - _ethCurrencySurplusAllowance
                        - _toEth(_usdCurrencySurplusAllowance) - _ethCurrencyPayoutLimit
                );

                // Make sure the fee was paid correctly.
                assertEq(
                    jbTerminalStore().balanceOf(
                        address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH
                    ),
                    _ethCurrencySurplusAllowance + _toEth(_usdCurrencySurplusAllowance)
                        - _beneficiaryEthBalance + _ethCurrencyPayoutLimit - _projectOwnerEthBalance
                );
                assertEq(
                    address(_terminal).balance,
                    _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
                );

                // Make sure the project owner got the expected number of tokens.
                // assertEq(_tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID), _unreservedPortion(PRBMath.mulDiv(_ethCurrencySurplusAllowance + _toEth(_usdCurrencySurplusAllowance) - _beneficiaryEthBalance + _ethCurrencyPayoutLimit - _projectOwnerEthBalance, _data.weight, 10 ** _ETH_DECIMALS)));
            }

            // Revert if the payout limit is greater than the balance.
            if (
                _ethCurrencyPayoutLimit <= _ethPayAmount
                    && _toEth(_usdCurrencyPayoutLimit) + _ethCurrencyPayoutLimit > _ethPayAmount
            ) {
                vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
            } else if (
                _ethCurrencyPayoutLimit > _ethPayAmount
                    && _toEth(_usdCurrencyPayoutLimit) > _ethPayAmount
            ) {
                vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
                // Revert if there's no payout limit.
            } else if (_usdCurrencyPayoutLimit == 0) {
                vm.expectRevert(abi.encodeWithSignature("PAYOUT_LIMIT_EXCEEDED()"));
            }

            // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
            _terminal.sendPayoutsOf({
                projectId: _projectId,
                amount: _usdCurrencyPayoutLimit,
                currency: uint32(uint160(address(_usdcToken))),
                token: JBTokenList.ETH,
                minReturnedTokens: 0
            });

            // Check the collected distribution if one is expected.
            if (
                _toEth(_usdCurrencyPayoutLimit) + _ethCurrencyPayoutLimit <= _ethPayAmount
                    && _usdCurrencyPayoutLimit > 0
            ) {
                // Make sure the project owner received the distributed funds.
                _projectOwnerEthBalance += (_toEth(_usdCurrencyPayoutLimit) * JBConstants.MAX_FEE)
                    / (_terminal.FEE() + JBConstants.MAX_FEE);
                assertEq(_projectOwner.balance, _projectOwnerEthBalance);
                assertEq(
                    jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                    _ethPayAmount - _ethCurrencySurplusAllowance
                        - _toEth(_usdCurrencySurplusAllowance) - _ethCurrencyPayoutLimit
                        - _toEth(_usdCurrencyPayoutLimit)
                );

                // Make sure the fee was paid correctly.
                assertEq(
                    jbTerminalStore().balanceOf(
                        address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH
                    ),
                    (
                        _ethCurrencySurplusAllowance + _toEth(_usdCurrencySurplusAllowance)
                            - _beneficiaryEthBalance
                    )
                        + (
                            _ethCurrencyPayoutLimit + _toEth(_usdCurrencyPayoutLimit)
                                - _projectOwnerEthBalance
                        )
                );
                assertEq(
                    address(_terminal).balance,
                    _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
                );
            }
        }

        // Keep a reference to the eth surplus left.
        uint256 _ethSurplus = _ethCurrencyPayoutLimit + _toEth(_usdCurrencyPayoutLimit)
            + _ethCurrencySurplusAllowance + _toEth(_usdCurrencySurplusAllowance) >= _ethPayAmount
            ? 0
            : _ethPayAmount - _ethCurrencyPayoutLimit - _toEth(_usdCurrencyPayoutLimit)
                - _ethCurrencySurplusAllowance - _toEth(_usdCurrencySurplusAllowance);

        // Keep a reference to the eth balance left.
        uint256 _ethBalance =
            _ethPayAmount - _ethCurrencySurplusAllowance - _toEth(_usdCurrencySurplusAllowance);
        if (_ethCurrencyPayoutLimit <= _ethPayAmount) {
            _ethBalance -= _ethCurrencyPayoutLimit;
            if (_toEth(_usdCurrencyPayoutLimit) + _ethCurrencyPayoutLimit < _ethPayAmount) {
                _ethBalance -= _toEth(_usdCurrencyPayoutLimit);
            }
        } else if (_toEth(_usdCurrencyPayoutLimit) <= _ethPayAmount) {
            _ethBalance -= _toEth(_usdCurrencyPayoutLimit);
        }

        // Make sure it's correct.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
            _ethBalance
        );

        // Make sure the usdc surplus is correct.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, address(_usdcToken)),
            _usdcPayAmount
        );

        // Make sure the total token supply is correct.
        assertEq(
            _controller.totalTokenSupplyWithReservedTokensOf(_projectId),
            PRBMath.mulDiv(
                _beneficiaryTokenBalance,
                JBConstants.MAX_RESERVED_RATE,
                JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate
            )
        );

        // Keep a reference to the amount of ETH being reclaimed.
        uint256 _ethReclaimAmount;

        vm.startPrank(_beneficiary);

        // If there's surplus.
        if (
            _toEth(PRBMath.mulDiv(_usdcPayAmount, 10 ** _ETH_DECIMALS, 10 ** _usdcToken.decimals()))
                + _ethSurplus > 0
        ) {
            // Get the expected amount reclaimed.
            _ethReclaimAmount = PRBMath.mulDiv(
                PRBMath.mulDiv(
                    _toEth(
                        PRBMath.mulDiv(
                            _usdcPayAmount, 10 ** _ETH_DECIMALS, 10 ** _usdcToken.decimals()
                        )
                    ) + _ethSurplus,
                    _beneficiaryTokenBalance,
                    PRBMath.mulDiv(
                        _beneficiaryTokenBalance,
                        JBConstants.MAX_RESERVED_RATE,
                        JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate
                    )
                ),
                _metadata.redemptionRate
                    + PRBMath.mulDiv(
                        _beneficiaryTokenBalance,
                        JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                        PRBMath.mulDiv(
                            _beneficiaryTokenBalance,
                            JBConstants.MAX_RESERVED_RATE,
                            JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate
                        )
                    ),
                JBConstants.MAX_REDEMPTION_RATE
            );

            // If there is more to reclaim than there is ETH in the tank.
            if (_ethReclaimAmount > _ethSurplus) {
                // Keep a reference to the amount to redeem for ETH, a proportion of available surplus in ETH.
                uint256 _tokenCountToRedeemForEth = PRBMath.mulDiv(
                    _beneficiaryTokenBalance,
                    _ethSurplus,
                    _ethSurplus
                        + _toEth(
                            PRBMath.mulDiv(
                                _usdcPayAmount, 10 ** _ETH_DECIMALS, 10 ** _usdcToken.decimals()
                            )
                        )
                );
                uint256 _tokenSupply = PRBMath.mulDiv(
                    _beneficiaryTokenBalance,
                    JBConstants.MAX_RESERVED_RATE,
                    JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate
                );
                // Redeem ETH from the surplus using only the _beneficiary's tokens needed to clear the ETH balance.
                _terminal.redeemTokensOf({
                    holder: _beneficiary,
                    projectId: _projectId,
                    count: _tokenCountToRedeemForEth,
                    token: JBTokenList.ETH,
                    minReclaimed: 0,
                    beneficiary: payable(_beneficiary),
                    metadata: new bytes(0)
                });

                // Redeem USDC from the surplus using only the _beneficiary's tokens needed to clear the USDC balance.
                _terminal.redeemTokensOf({
                    holder: _beneficiary,
                    projectId: _projectId,
                    count: _beneficiaryTokenBalance - _tokenCountToRedeemForEth,
                    token: address(_usdcToken),
                    minReclaimed: 0,
                    beneficiary: payable(_beneficiary),
                    metadata: new bytes(0)
                });

                _ethReclaimAmount = PRBMath.mulDiv(
                    PRBMath.mulDiv(
                        _toEth(
                            PRBMath.mulDiv(
                                _usdcPayAmount, 10 ** _ETH_DECIMALS, 10 ** _usdcToken.decimals()
                            )
                        ) + _ethSurplus,
                        _tokenCountToRedeemForEth,
                        _tokenSupply
                    ),
                    _metadata.redemptionRate
                        + PRBMath.mulDiv(
                            _tokenCountToRedeemForEth,
                            JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                            _tokenSupply
                        ),
                    JBConstants.MAX_REDEMPTION_RATE
                );

                uint256 _usdcReclaimAmount = PRBMath.mulDiv(
                    PRBMath.mulDiv(
                        _usdcPayAmount
                            + _toUsd(
                                PRBMath.mulDiv(
                                    _ethSurplus - _ethReclaimAmount,
                                    10 ** _usdcToken.decimals(),
                                    10 ** _ETH_DECIMALS
                                )
                            ),
                        _beneficiaryTokenBalance - _tokenCountToRedeemForEth,
                        _tokenSupply - _tokenCountToRedeemForEth
                    ),
                    _metadata.redemptionRate
                        + PRBMath.mulDiv(
                            _beneficiaryTokenBalance - _tokenCountToRedeemForEth,
                            JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                            _tokenSupply - _tokenCountToRedeemForEth
                        ),
                    JBConstants.MAX_REDEMPTION_RATE
                );

                assertEq(
                    jbTerminalStore().balanceOf(address(_terminal), _projectId, address(_usdcToken)),
                    _usdcPayAmount - _usdcReclaimAmount
                );

                uint256 _usdcFeeAmount = _usdcReclaimAmount
                    - _usdcReclaimAmount * JBConstants.MAX_FEE / (_terminal.FEE() + JBConstants.MAX_FEE);
                assertEq(_usdcToken.balanceOf(_beneficiary), _usdcReclaimAmount - _usdcFeeAmount);

                // Make sure the fee was paid correctly.
                assertEq(
                    jbTerminalStore().balanceOf(
                        address(_terminal), _FEE_PROJECT_ID, address(_usdcToken)
                    ),
                    _usdcFeeAmount
                );
                assertEq(
                    _usdcToken.balanceOf(address(_terminal)),
                    _usdcPayAmount - _usdcReclaimAmount + _usdcFeeAmount
                );
            } else {
                // Redeem ETH from the surplus using all of the _beneficiary's tokens.
                _terminal.redeemTokensOf({
                    holder: _beneficiary,
                    projectId: _projectId,
                    count: _beneficiaryTokenBalance,
                    token: JBTokenList.ETH,
                    minReclaimed: 0,
                    beneficiary: payable(_beneficiary),
                    metadata: new bytes(0)
                });
            }
            // burn the tokens.
        } else {
            _terminal.redeemTokensOf({
                holder: _beneficiary,
                projectId: _projectId,
                count: _beneficiaryTokenBalance,
                token: address(_usdcToken),
                minReclaimed: 0,
                beneficiary: payable(_beneficiary),
                metadata: new bytes(0)
            });
        }
        vm.stopPrank();

        // Make sure the balance is adjusted by the reclaim amount.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
            _ethBalance - _ethReclaimAmount
        );
    }

    // Project 2 accepts ETH into _terminal and USDC into _terminal2.
    // Project 1 accepts USDC and ETH fees into _terminal.
    function testFuzzMultiTerminalAllowance(
        uint224 _ethCurrencySurplusAllowance,
        uint224 _ethCurrencyPayoutLimit,
        uint256 _ethPayAmount,
        uint224 _usdCurrencySurplusAllowance,
        uint224 _usdCurrencyPayoutLimit,
        uint256 _usdcPayAmount
    ) public {
        // Make sure the amount of eth to pay is bounded.
        _ethPayAmount = bound(_ethPayAmount, 0, 1_000_000 * 10 ** _ETH_DECIMALS);
        _usdcPayAmount = bound(_usdcPayAmount, 0, 1_000_000 * 10 ** _usdcToken.decimals());
        _usdCurrencyPayoutLimit = uint224(
            bound(
                _usdCurrencyPayoutLimit,
                0,
                type(uint224).max / 10 ** (_ETH_DECIMALS - _usdcToken.decimals())
            )
        );

        // Make sure the values don't surplus the registry.
        unchecked {
            vm.assume(
                _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit
                    >= _ethCurrencySurplusAllowance
                    && _ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit >= _ethCurrencyPayoutLimit
            );
            vm.assume(
                _usdCurrencySurplusAllowance + _usdCurrencyPayoutLimit
                    >= _usdCurrencySurplusAllowance
                    && _usdCurrencySurplusAllowance + _usdCurrencyPayoutLimit >= _usdCurrencyPayoutLimit
            );
        }

        {
            // Package up the limits for the given terminal.
            JBFundAccessLimitGroup[] memory _fundAccessLimitGroup = new JBFundAccessLimitGroup[](2);

            // Specify a payout limit.
            JBCurrencyAmount[] memory _payoutLimits1 = new JBCurrencyAmount[](1);
            JBCurrencyAmount[] memory _payoutLimits2 = new JBCurrencyAmount[](1);
            _payoutLimits1[0] = JBCurrencyAmount({
                amount: _ethCurrencyPayoutLimit,
                currency: uint32(uint160(JBTokenList.ETH))
            });
            _payoutLimits2[0] = JBCurrencyAmount({
                amount: _usdCurrencyPayoutLimit,
                currency: uint32(uint160(address(_usdcToken)))
            });

            // Specify a surplus allowance.
            JBCurrencyAmount[] memory _surplusAllowances1 = new JBCurrencyAmount[](1);
            JBCurrencyAmount[] memory _surplusAllowances2 = new JBCurrencyAmount[](1);
            _surplusAllowances1[0] = JBCurrencyAmount({
                amount: _ethCurrencySurplusAllowance,
                currency: uint32(uint160(JBTokenList.ETH))
            });
            _surplusAllowances2[0] = JBCurrencyAmount({
                amount: _usdCurrencySurplusAllowance,
                currency: uint32(uint160(address(_usdcToken)))
            });

            _fundAccessLimitGroup[0] = JBFundAccessLimitGroup({
                terminal: address(_terminal),
                token: JBTokenList.ETH,
                payoutLimits: _payoutLimits1,
                surplusAllowances: _surplusAllowances1
            });

            _fundAccessLimitGroup[1] = JBFundAccessLimitGroup({
                terminal: address(_terminal2),
                token: address(_usdcToken),
                payoutLimits: _payoutLimits2,
                surplusAllowances: _surplusAllowances2
            });

            // Package up the configuration info.
            JBRulesetConfig[] memory _rulesetConfigurations = new JBRulesetConfig[](1);
            _rulesetConfigurations[0].mustStartAtOrAfter = 0;
            _rulesetConfigurations[0].data = _data;
            _rulesetConfigurations[0].metadata = _metadata;
            _rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
            _rulesetConfigurations[0].fundAccessLimitGroup = _fundAccessLimitGroup;

            JBTerminalConfig[] memory _terminalConfigurations1 = new JBTerminalConfig[](1);
            JBTerminalConfig[] memory _terminalConfigurations2 = new JBTerminalConfig[](2);
            JBAccountingContextConfig[] memory _accountingContextConfigs1 =
                new JBAccountingContextConfig[](2);
            JBAccountingContextConfig[] memory _accountingContextConfigs2 =
                new JBAccountingContextConfig[](1);
            JBAccountingContextConfig[] memory _accountingContextConfigs3 =
                new JBAccountingContextConfig[](1);
            _accountingContextConfigs1[0] = JBAccountingContextConfig({
                token: JBTokenList.ETH,
                standard: JBTokenStandards.NATIVE
            });
            _accountingContextConfigs1[1] = JBAccountingContextConfig({
                token: address(_usdcToken),
                standard: JBTokenStandards.ERC20
            });
            _accountingContextConfigs2[0] = JBAccountingContextConfig({
                token: JBTokenList.ETH,
                standard: JBTokenStandards.NATIVE
            });
            _accountingContextConfigs3[0] = JBAccountingContextConfig({
                token: address(_usdcToken),
                standard: JBTokenStandards.ERC20
            });

            // Fee takes USDC and ETH in same terminal
            _terminalConfigurations1[0] = JBTerminalConfig({
                terminal: _terminal,
                accountingContextConfigs: _accountingContextConfigs1
            });
            _terminalConfigurations2[0] = JBTerminalConfig({
                terminal: _terminal,
                accountingContextConfigs: _accountingContextConfigs2
            });
            _terminalConfigurations2[1] = JBTerminalConfig({
                terminal: _terminal2,
                accountingContextConfigs: _accountingContextConfigs3
            });

            // First project for fee collection
            _controller.launchProjectFor({
                owner: address(420), // random
                projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
                rulesetConfigurations: _rulesetConfigurations, // use the same cycle configs
                terminalConfigurations: _terminalConfigurations1, // set terminals where fees will be received
                memo: ""
            });

            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: JBProjectMetadata({content: "myIPFSHash", domain: 1}),
                rulesetConfigurations: _rulesetConfigurations,
                terminalConfigurations: _terminalConfigurations2,
                memo: ""
            });
        }

        // Add a price feed to convert from ETH to USD currencies.
        {
            vm.startPrank(_projectOwner);
            MockPriceFeed _priceFeedEthUsd =
                new MockPriceFeed(_USD_PRICE_PER_ETH, _PRICE_FEED_DECIMALS);
            vm.label(address(_priceFeedEthUsd), "MockPrice Feed ETH-USDC");

            _prices.addPriceFeedFor({
                projectId: 0,
                pricingCurrency: uint32(uint160(address(_usdcToken))),
                unitCurrency: uint32(uint160(JBTokenList.ETH)),
                priceFeed: _priceFeedEthUsd
            });

            vm.stopPrank();
        }

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId,
            amount: _ethPayAmount,
            token: JBTokenList.ETH,
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens from the ETH payment.
        uint256 _beneficiaryTokenBalance =
            _unreservedPortion(PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS));
        assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);
        // Deal usdc to this contract.
        _usdcToken.mint(address(this), _usdcPayAmount);

        // Allow the terminal to spend the usdc.
        _usdcToken.approve(address(_terminal2), _usdcPayAmount);

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal2.pay({
            projectId: _projectId,
            amount: _usdcPayAmount,
            token: address(_usdcToken),
            beneficiary: _beneficiary,
            minReturnedTokens: 0,
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the terminal holds the full ETH balance.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
            _ethPayAmount
        );
        // Make sure the usdc is accounted for.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal2), _projectId, address(_usdcToken)),
            _usdcPayAmount
        );
        assertEq(_usdcToken.balanceOf(address(_terminal2)), _usdcPayAmount);

        {
            // Convert the usd amount to an eth amount, byway of the current weight used for issuance.
            uint256 _usdWeightedPayAmountConvertedToEth = PRBMath.mulDiv(
                _usdcPayAmount,
                _data.weight,
                PRBMath.mulDiv(
                    _USD_PRICE_PER_ETH, 10 ** _usdcToken.decimals(), 10 ** _PRICE_FEED_DECIMALS
                )
            );

            // Make sure the beneficiary got the expected number of tokens from the USDC payment.
            _beneficiaryTokenBalance += _unreservedPortion(_usdWeightedPayAmountConvertedToEth);
            assertEq(_tokens.totalBalanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);
        }

        // Revert if there's no ETH allowance.
        if (_ethCurrencySurplusAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        } else if (_ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary ETH allowance of surplus.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethCurrencySurplusAllowance,
            currency: uint32(uint160(JBTokenList.ETH)),
            token: JBTokenList.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's ETH balance;
        uint256 _beneficiaryEthBalance;

        // Check the collected balance if one is expected.
        if (_ethCurrencySurplusAllowance + _ethCurrencyPayoutLimit <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance = PRBMath.mulDiv(
                _ethCurrencySurplusAllowance,
                JBConstants.MAX_FEE,
                JBConstants.MAX_FEE + _terminal.FEE()
            );
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                _ethPayAmount - _ethCurrencySurplusAllowance
            );

            // Make sure the fee was paid correctly.
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH),
                _ethCurrencySurplusAllowance - _beneficiaryEthBalance
            );
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(
                _tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID),
                _unreservedPortion(
                    PRBMath.mulDiv(
                        _ethCurrencySurplusAllowance - _beneficiaryEthBalance,
                        _data.weight,
                        10 ** _ETH_DECIMALS
                    )
                )
            );
        } else {
            // Set the eth surplus allowance value to 0 if it wasnt used.
            _ethCurrencySurplusAllowance = 0;
        }

        // Revert if there's no ETH allowance.
        if (_usdCurrencySurplusAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
            // revert if the usd surplus allowance resolved to eth is greater than 0, and there is sufficient surplus to pull from including what was already pulled from.
        } else if (_usdCurrencySurplusAllowance + _usdCurrencyPayoutLimit > _usdcPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary ETH allowance of surplus.
        vm.prank(_projectOwner);
        _terminal2.useAllowanceOf({
            projectId: _projectId,
            amount: _usdCurrencySurplusAllowance,
            currency: uint32(uint160(address(_usdcToken))),
            token: address(_usdcToken),
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's USDC balance;
        uint256 _beneficiaryUsdcBalance;

        // Check the collected balance if one is expected.
        if (_usdCurrencySurplusAllowance + _usdCurrencyPayoutLimit <= _usdcPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryUsdcBalance += PRBMath.mulDiv(
                _usdCurrencySurplusAllowance,
                JBConstants.MAX_FEE,
                JBConstants.MAX_FEE + _terminal.FEE()
            );
            assertEq(_usdcToken.balanceOf(_beneficiary), _beneficiaryUsdcBalance);
            assertEq(
                jbTerminalStore().balanceOf(address(_terminal2), _projectId, address(_usdcToken)),
                _usdcPayAmount - _usdCurrencySurplusAllowance
            );

            // Make sure the fee was paid correctly.
            assertEq(
                jbTerminalStore().balanceOf(
                    address(_terminal), _FEE_PROJECT_ID, address(_usdcToken)
                ),
                _usdCurrencySurplusAllowance - _beneficiaryUsdcBalance
            );
            assertEq(
                _usdcToken.balanceOf(address(_terminal2)),
                _usdcPayAmount - _usdCurrencySurplusAllowance
            );
            assertEq(
                _usdcToken.balanceOf(address(_terminal)),
                _usdCurrencySurplusAllowance - _beneficiaryUsdcBalance
            );

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(
                _tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID),
                _unreservedPortion(
                    PRBMath.mulDiv(
                        _ethCurrencySurplusAllowance
                            + _toEth(
                                PRBMath.mulDiv(
                                    _usdCurrencySurplusAllowance,
                                    10 ** _ETH_DECIMALS,
                                    10 ** _usdcToken.decimals()
                                )
                            ) - _beneficiaryEthBalance
                            - _toEth(
                                PRBMath.mulDiv(
                                    _beneficiaryUsdcBalance,
                                    10 ** _ETH_DECIMALS,
                                    10 ** _usdcToken.decimals()
                                )
                            ),
                        _data.weight,
                        10 ** _ETH_DECIMALS
                    )
                )
            );
        } else {
            // Set the eth surplus allowance value to 0 if it wasnt used.
            _usdCurrencySurplusAllowance = 0;
        }

        // Payout limits
        {
            // Revert if the payout limit is greater than the balance.
            if (_ethCurrencyPayoutLimit > _ethPayAmount) {
                vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
                // Revert if there's no payout limit.
            } else if (_ethCurrencyPayoutLimit == 0) {
                vm.expectRevert(abi.encodeWithSignature("PAYOUT_LIMIT_EXCEEDED()"));
            }

            // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
            _terminal.sendPayoutsOf({
                projectId: _projectId,
                amount: _ethCurrencyPayoutLimit,
                currency: uint32(uint160(JBTokenList.ETH)),
                token: JBTokenList.ETH,
                minReturnedTokens: 0
            });

            uint256 _projectOwnerEthBalance;

            // Check the collected distribution if one is expected.
            if (_ethCurrencyPayoutLimit <= _ethPayAmount && _ethCurrencyPayoutLimit != 0) {
                // Make sure the project owner received the distributed funds.
                _projectOwnerEthBalance = (_ethCurrencyPayoutLimit * JBConstants.MAX_FEE)
                    / (_terminal.FEE() + JBConstants.MAX_FEE);
                assertEq(_projectOwner.balance, _projectOwnerEthBalance);
                assertEq(
                    jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
                    _ethPayAmount - _ethCurrencySurplusAllowance - _ethCurrencyPayoutLimit
                );

                // Make sure the fee was paid correctly.
                assertEq(
                    jbTerminalStore().balanceOf(
                        address(_terminal), _FEE_PROJECT_ID, JBTokenList.ETH
                    ),
                    _ethCurrencySurplusAllowance - _beneficiaryEthBalance + _ethCurrencyPayoutLimit
                        - _projectOwnerEthBalance
                );
                assertEq(
                    address(_terminal).balance,
                    _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance
                );

                // Make sure the project owner got the expected number of tokens.
                // assertEq(_tokens.totalBalanceOf(_projectOwner, _FEE_PROJECT_ID), _unreservedPortion(PRBMath.mulDiv(_ethCurrencySurplusAllowance + _toEth(_usdCurrencySurplusAllowance) - _beneficiaryEthBalance + _ethCurrencyPayoutLimit - _projectOwnerEthBalance, _data.weight, 10 ** _ETH_DECIMALS)));
            }

            // Revert if the payout limit is greater than the balance.
            if (_usdCurrencyPayoutLimit > _usdcPayAmount) {
                vm.expectRevert(abi.encodeWithSignature("INADEQUATE_TERMINAL_STORE_BALANCE()"));
                // Revert if there's no payout limit.
            } else if (_usdCurrencyPayoutLimit == 0) {
                vm.expectRevert(abi.encodeWithSignature("PAYOUT_LIMIT_EXCEEDED()"));
            }

            // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
            _terminal2.sendPayoutsOf({
                projectId: _projectId,
                amount: _usdCurrencyPayoutLimit,
                currency: uint32(uint160(address(_usdcToken))),
                token: address(_usdcToken),
                minReturnedTokens: 0
            });

            uint256 _projectOwnerUsdcBalance;

            // Check the collected distribution if one is expected.
            if (_usdCurrencyPayoutLimit <= _usdcPayAmount && _usdCurrencyPayoutLimit != 0) {
                // Make sure the project owner received the distributed funds.
                _projectOwnerUsdcBalance = (_usdCurrencyPayoutLimit * JBConstants.MAX_FEE)
                    / (_terminal.FEE() + JBConstants.MAX_FEE);
                assertEq(_usdcToken.balanceOf(_projectOwner), _projectOwnerUsdcBalance);
                assertEq(
                    jbTerminalStore().balanceOf(
                        address(_terminal2), _projectId, address(_usdcToken)
                    ),
                    _usdcPayAmount - _usdCurrencySurplusAllowance - _usdCurrencyPayoutLimit
                );

                // Make sure the fee was paid correctly.
                assertEq(
                    jbTerminalStore().balanceOf(
                        address(_terminal), _FEE_PROJECT_ID, address(_usdcToken)
                    ),
                    _usdCurrencySurplusAllowance - _beneficiaryUsdcBalance + _usdCurrencyPayoutLimit
                        - _projectOwnerUsdcBalance
                );
                assertEq(
                    _usdcToken.balanceOf(address(_terminal2)),
                    _usdcPayAmount - _usdCurrencySurplusAllowance - _usdCurrencyPayoutLimit
                );
                assertEq(
                    _usdcToken.balanceOf(address(_terminal)),
                    _usdCurrencySurplusAllowance + _usdCurrencyPayoutLimit - _beneficiaryUsdcBalance
                        - _projectOwnerUsdcBalance
                );
            }
        }

        // Keep a reference to the eth surplus left.
        uint256 _ethSurplus = _ethCurrencyPayoutLimit + _ethCurrencySurplusAllowance
            >= _ethPayAmount
            ? 0
            : _ethPayAmount - _ethCurrencyPayoutLimit - _ethCurrencySurplusAllowance;

        uint256 _usdcSurplus = _usdCurrencyPayoutLimit + _usdCurrencySurplusAllowance
            >= _usdcPayAmount
            ? 0
            : _usdcPayAmount - _usdCurrencyPayoutLimit - _usdCurrencySurplusAllowance;

        // Keep a reference to the eth balance left.
        uint256 _usdcBalanceInTerminal = _usdcPayAmount - _usdCurrencySurplusAllowance;

        if (_usdCurrencyPayoutLimit <= _usdcPayAmount) {
            _usdcBalanceInTerminal -= _usdCurrencyPayoutLimit;
        }

        assertEq(_usdcToken.balanceOf(address(_terminal2)), _usdcBalanceInTerminal);

        // Make sure the total token supply is correct.
        assertEq(
            jbController().totalTokenSupplyWithReservedTokensOf(_projectId),
            PRBMath.mulDiv(
                _beneficiaryTokenBalance,
                JBConstants.MAX_RESERVED_RATE,
                JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate
            )
        );

        // Keep a reference to the amount of ETH being reclaimed.
        uint256 _ethReclaimAmount;

        vm.startPrank(_beneficiary);

        // If there's ETH surplus.
        if (
            _ethSurplus
                + _toEth(PRBMath.mulDiv(_usdcSurplus, 10 ** _ETH_DECIMALS, 10 ** _usdcToken.decimals()))
                > 0
        ) {
            // Get the expected amount reclaimed.
            _ethReclaimAmount = PRBMath.mulDiv(
                PRBMath.mulDiv(
                    _ethSurplus
                        + _toEth(
                            PRBMath.mulDiv(
                                _usdcSurplus, 10 ** _ETH_DECIMALS, 10 ** _usdcToken.decimals()
                            )
                        ),
                    _beneficiaryTokenBalance,
                    PRBMath.mulDiv(
                        _beneficiaryTokenBalance,
                        JBConstants.MAX_RESERVED_RATE,
                        JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate
                    )
                ),
                _metadata.redemptionRate
                    + PRBMath.mulDiv(
                        _beneficiaryTokenBalance,
                        JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                        PRBMath.mulDiv(
                            _beneficiaryTokenBalance,
                            JBConstants.MAX_RESERVED_RATE,
                            JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate
                        )
                    ),
                JBConstants.MAX_REDEMPTION_RATE
            );

            // If there is more to reclaim than there is ETH in the tank.
            if (_ethReclaimAmount > _ethSurplus) {
                uint256 _usdcReclaimAmount;
                {
                    // Keep a reference to the amount to redeem for ETH, a proportion of available surplus in ETH.
                    uint256 _tokenCountToRedeemForEth = PRBMath.mulDiv(
                        _beneficiaryTokenBalance,
                        _ethSurplus,
                        _ethSurplus
                            + _toEth(
                                PRBMath.mulDiv(
                                    _usdcSurplus, 10 ** _ETH_DECIMALS, 10 ** _usdcToken.decimals()
                                )
                            )
                    );
                    uint256 _tokenSupply = PRBMath.mulDiv(
                        _beneficiaryTokenBalance,
                        JBConstants.MAX_RESERVED_RATE,
                        JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate
                    );
                    // Redeem ETH from the surplus using only the _beneficiary's tokens needed to clear the ETH balance.
                    _terminal.redeemTokensOf({
                        holder: _beneficiary,
                        projectId: _projectId,
                        count: _tokenCountToRedeemForEth,
                        token: JBTokenList.ETH,
                        minReclaimed: 0,
                        beneficiary: payable(_beneficiary),
                        metadata: new bytes(0)
                    });

                    // Redeem USDC from the surplus using only the _beneficiary's tokens needed to clear the USDC balance.
                    _terminal2.redeemTokensOf({
                        holder: _beneficiary,
                        projectId: _projectId,
                        count: _beneficiaryTokenBalance - _tokenCountToRedeemForEth,
                        token: address(_usdcToken),
                        minReclaimed: 0,
                        beneficiary: payable(_beneficiary),
                        metadata: new bytes(0)
                    });

                    _ethReclaimAmount = PRBMath.mulDiv(
                        PRBMath.mulDiv(
                            _ethSurplus
                                + _toEth(
                                    PRBMath.mulDiv(
                                        _usdcSurplus, 10 ** _ETH_DECIMALS, 10 ** _usdcToken.decimals()
                                    )
                                ),
                            _tokenCountToRedeemForEth,
                            _tokenSupply
                        ),
                        _metadata.redemptionRate
                            + PRBMath.mulDiv(
                                _tokenCountToRedeemForEth,
                                JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                                _tokenSupply
                            ),
                        JBConstants.MAX_REDEMPTION_RATE
                    );
                    _usdcReclaimAmount = PRBMath.mulDiv(
                        PRBMath.mulDiv(
                            _usdcSurplus
                                + _toUsd(
                                    PRBMath.mulDiv(
                                        _ethSurplus - _ethReclaimAmount,
                                        10 ** _usdcToken.decimals(),
                                        10 ** _ETH_DECIMALS
                                    )
                                ),
                            _beneficiaryTokenBalance - _tokenCountToRedeemForEth,
                            _tokenSupply - _tokenCountToRedeemForEth
                        ),
                        _metadata.redemptionRate
                            + PRBMath.mulDiv(
                                _beneficiaryTokenBalance - _tokenCountToRedeemForEth,
                                JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                                _tokenSupply - _tokenCountToRedeemForEth
                            ),
                        JBConstants.MAX_REDEMPTION_RATE
                    );
                }

                assertEq(
                    jbTerminalStore().balanceOf(
                        address(_terminal2), _projectId, address(_usdcToken)
                    ),
                    _usdcSurplus - _usdcReclaimAmount
                );

                uint256 _usdcFeeAmount = _usdcReclaimAmount
                    - _usdcReclaimAmount * JBConstants.MAX_FEE / (_terminal.FEE() + JBConstants.MAX_FEE);

                _beneficiaryUsdcBalance += _usdcReclaimAmount - _usdcFeeAmount;
                assertEq(_usdcToken.balanceOf(_beneficiary), _beneficiaryUsdcBalance);

                assertEq(
                    _usdcToken.balanceOf(address(_terminal2)),
                    _usdcBalanceInTerminal - _usdcReclaimAmount
                );

                // Only the fees left
                assertEq(
                    _usdcToken.balanceOf(address(_terminal)),
                    _usdcPayAmount - _usdcToken.balanceOf(address(_terminal2))
                        - _usdcToken.balanceOf(_beneficiary) - _usdcToken.balanceOf(_projectOwner)
                );
            } else {
                // Redeem ETH from the surplus using all of the _beneficiary's tokens.
                _terminal.redeemTokensOf({
                    holder: _beneficiary,
                    projectId: _projectId,
                    count: _beneficiaryTokenBalance,
                    token: JBTokenList.ETH,
                    minReclaimed: 0,
                    beneficiary: payable(_beneficiary),
                    metadata: new bytes(0)
                });
            }
            // burn the tokens.
        } else {
            _terminal2.redeemTokensOf({
                holder: _beneficiary,
                projectId: _projectId,
                count: _beneficiaryTokenBalance,
                token: address(_usdcToken),
                minReclaimed: 0,
                beneficiary: payable(_beneficiary),
                metadata: new bytes(0)
            });
        }
        vm.stopPrank();

        // Keep a reference to the eth balance left.
        uint256 _projectEthBalance = _ethPayAmount - _ethCurrencySurplusAllowance;
        if (_ethCurrencyPayoutLimit <= _ethPayAmount) {
            _projectEthBalance -= _ethCurrencyPayoutLimit;
        }

        // Make sure the balance is adjusted by the reclaim amount.
        assertEq(
            jbTerminalStore().balanceOf(address(_terminal), _projectId, JBTokenList.ETH),
            _projectEthBalance - _ethReclaimAmount
        );
    }

    function _toEth(uint256 _usdVal) internal pure returns (uint256) {
        return PRBMath.mulDiv(_usdVal, 10 ** _PRICE_FEED_DECIMALS, _USD_PRICE_PER_ETH);
    }

    function _toUsd(uint256 _ethVal) internal pure returns (uint256) {
        return PRBMath.mulDiv(_ethVal, _USD_PRICE_PER_ETH, 10 ** _PRICE_FEED_DECIMALS);
    }

    function _unreservedPortion(uint256 _fullPortion) internal view returns (uint256) {
        return PRBMath.mulDiv(
            _fullPortion,
            JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate,
            JBConstants.MAX_RESERVED_RATE
        );
    }
}
