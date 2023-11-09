// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import /* {*} from */ "./helpers/TestBaseWorkflow.sol";
import {MockPriceFeed} from './mock/MockPriceFeed.sol';

/// Funds can be accessed in three ways:
/// 1. project owners set a distribution limit to prioritize spending to pre-determined destinations. funds being removed from the protocol incurs fees.
/// 2. project owners set an overflow allowance to allow spending funds from the treasury in excess of the distribution limit. incurs fees.
/// 3. token holders can redeem tokens to access funds in excess of the distribution limit. incurs fees if the redemption rate != 100%.
/// Each of these incurs protocol fees if the project with ID #1 accepts the token being accessed.
contract TestAccessToFunds_Local is TestBaseWorkflow {
    uint256 private constant _FEE_PROJECT_ID = 1; 
    uint8 private constant _WEIGHT_DECIMALS = 18; // FIXED 
    uint8 private constant _ETH_DECIMALS = 17;
    uint8 private constant _USDC_DECIMALS = 6; 
    uint8 private constant _PRICE_FEED_DECIMALS = 10; 
    uint256 private constant _USDC_PRICE_PER_ETH = 2000 * 10**_PRICE_FEED_DECIMALS; // 2000 USDC == 1 ETH
    
    IJBController3_1 private _controller;
    IJBPrices private _prices;
    IJBPayoutRedemptionTerminal private _terminal; 
    IJBTokenStore private _tokenStore;
    address private _projectOwner;
    address private _beneficiary;
    MockERC20 private _usdcToken;

    JBProjectMetadata private _projectMetadata;
    JBFundingCycleData private _data;
    JBFundingCycleMetadata private _metadata;
    IJBPaymentTerminal[] private _terminals;

    function setUp() public override {
        super.setUp();

        _projectOwner = multisig();
        _beneficiary = beneficiary();
        _usdcToken = usdcToken();
        _tokenStore = jbTokenStore();
        _controller = jbController();
        _prices = jbPrices();
        _terminal = jbPayoutRedemptionTerminal();
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});
        _data = JBFundingCycleData({
            duration: 0,
            weight: 1000 * 10 ** _WEIGHT_DECIMALS,
            discountRate: 0,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false,
                pauseTransfers: false
            }),
            reservedRate:  JBConstants.MAX_RESERVED_RATE / 2, //50%
            redemptionRate:  JBConstants.MAX_REDEMPTION_RATE / 2, //50%
            baseCurrency: JBCurrencies.ETH,
            pausePay: false,
            pauseDistributions: false,
            pauseRedeem: false,
            pauseBurn: false,
            allowMinting: false,
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

        _terminals.push(_terminal);
    }
    
    // Tests that basic distribution limit and overflow allowance constraints work as intended.
    function testETHAllowance() public {
        // Hardcode values to use.
        uint256 _ethDistributionLimit = 10 * 10**_ETH_DECIMALS;
        uint256 _ethOverflowAllowance = 5 * 10**_ETH_DECIMALS;

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        {
            // Specify a distribution limit.
            JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
            _distributionLimits[0] = JBCurrencyAmount({
                value: _ethDistributionLimit,
                currency: JBCurrencies.ETH
            });  

            // Specify an overflow allowance.
            JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
            _overflowAllowances[0] = JBCurrencyAmount({
                value: _ethOverflowAllowance,
                currency: JBCurrencies.ETH
            });

            _fundAccessConstraints[0] =
                JBFundAccessConstraints({
                    terminal: _terminal,
                    token: JBTokens.ETH, 
                    distributionLimits: _distributionLimits,
                    overflowAllowances: _overflowAllowances
                });
        }

        // Keep references to the projects.
        uint256 _projectId;

        {
            // Package up the configuration info.
            JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
            _cycleConfig[0].mustStartAtOrAfter = 0;
            _cycleConfig[0].data = _data;
            _cycleConfig[0].metadata = _metadata;
            _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
            _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

            // First project for fee collection
            _controller.launchProjectFor({
                owner: address(420), // random
                projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
                configurations: _cycleConfig,
                terminals: _terminals, // set terminals where fees will be received
                memo: ""
            });

            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: _projectMetadata,
                configurations: _cycleConfig,
                terminals: _terminals,
                memo: ""
            });
            
        }

        // Set the fee collecting terminal's ETH accounting context.
        _terminal.setTokenAccountingContextFor({
            projectId: _FEE_PROJECT_ID,
            token: JBTokens.ETH,
            decimals:_ETH_DECIMALS,
            currency: uint32(JBCurrencies.ETH)
        });

        // Set the test project's terminal's ETH accounting context.
        _terminal.setTokenAccountingContextFor({
            projectId: _projectId,
            token: JBTokens.ETH,
            decimals: _ETH_DECIMALS,
            currency: uint32(JBCurrencies.ETH)
        });

        // Get a reference to the amount being paid, such that the distribution limit is met with two times the overflow than is allowed to be withdrawn.
        uint256 _ethPayAmount = _ethDistributionLimit + (2 * _ethOverflowAllowance);
        
        // Pay the project such that the _beneficiary receives project tokens.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId, 
            amount: _ethPayAmount, 
            token: JBTokens.ETH, 
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            metadata: new bytes(0)
        }); 

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount);

        // Use the full discretionary allowance of overflow.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethOverflowAllowance,
            currency: JBCurrencies.ETH,
            token: JBTokens.ETH,
            minReturnedTokens: 0, 
            beneficiary: payable(_beneficiary),
            memo: "MEMO"
        });
        
        // Make sure the beneficiary received the funds and that they are no longer in the terminal.
        uint256 _beneficiaryBalance = PRBMath.mulDiv(_ethOverflowAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
        assertEq(_beneficiary.balance, _beneficiaryBalance);
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethOverflowAllowance);

        // Make sure the fee was paid correctly.
        assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), _ethOverflowAllowance - _beneficiaryBalance);
        assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance);

        // Make sure the project owner got the expected number of tokens.
        assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv(_ethOverflowAllowance - _beneficiaryBalance, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _ethDistributionLimit,
            currency: JBCurrencies.ETH,
            token: JBTokens.ETH,
            minReturnedTokens: 0
        });

        // Make sure the project owner received the distributed funds.
        uint256 _projectOwnerBalance = (_ethDistributionLimit * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);

        // Make sure the project owner received the full amount.
        assertEq(_projectOwner.balance, _projectOwnerBalance);
        
        // Make sure the fee was paid correctly.
        assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance));
        assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance);

        // Make sure the project owner got the expected number of tokens.
        assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv((_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance), _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);

        // Redeem ETH from the overflow using all of the _beneficiary's tokens.
        vm.prank(_beneficiary);
        _terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            token: JBTokens.ETH,
            tokenCount: _beneficiaryTokenBalance,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            metadata: new bytes(0)
        });

        // Make sure the beneficiary doesn't have tokens left.
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), 0);

        // Get the expected amount reclaimed.
        uint256 _reclaimAmount = (PRBMath.mulDiv(
            PRBMath.mulDiv(_ethPayAmount - _ethOverflowAllowance - _ethDistributionLimit, _beneficiaryTokenBalance, PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)),
            _metadata.redemptionRate +
            PRBMath.mulDiv(
                _beneficiaryTokenBalance,
                JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
            ),
            JBConstants.MAX_REDEMPTION_RATE
        ));

        // Calculate the fee from the redemption.
        uint256 _feeAmount = _reclaimAmount - _reclaimAmount * JBConstants.MAX_FEE / (_terminal.fee() + JBConstants.MAX_FEE);
        assertEq(_beneficiary.balance, _beneficiaryBalance + _reclaimAmount - _feeAmount);
        
        // // Make sure the fee was paid correctly.
        assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance) + _feeAmount);
        assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance - (_reclaimAmount - _feeAmount));

        // Make sure the project owner got the expected number of tokens from the fee.
        assertEq(_tokenStore.balanceOf(_beneficiary, _FEE_PROJECT_ID), PRBMath.mulDiv(_feeAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
    }

    function testFuzzETHAllowance(uint232 _ethOverflowAllowance, uint232 _ethDistributionLimit, uint256 _ethPayAmount) public {
        // Make sure the amount of eth to pay is bounded. 
        _ethPayAmount = bound(_ethPayAmount, 0, 1000000 * 10**_ETH_DECIMALS);

        // Make sure the values don't overflow the registry.
        unchecked {
            vm.assume(_ethOverflowAllowance + _ethDistributionLimit >= _ethOverflowAllowance && _ethOverflowAllowance + _ethDistributionLimit >= _ethDistributionLimit);
        }

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        {
            // Specify a distribution limit.
            JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
            _distributionLimits[0] = JBCurrencyAmount({
                value: _ethDistributionLimit,
                currency: JBCurrencies.ETH
            });  

            // Specify an overflow allowance.
            JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
            _overflowAllowances[0] = JBCurrencyAmount({
                value: _ethOverflowAllowance,
                currency: JBCurrencies.ETH 
            });

            _fundAccessConstraints[0] =
                JBFundAccessConstraints({
                    terminal: _terminal,
                    token: JBTokens.ETH,
                    distributionLimits: _distributionLimits,
                    overflowAllowances: _overflowAllowances
                });
        }

        // Keep references to the projects.
        uint256 _projectId;

        {
            // Package up the configuration info.
            JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
            _cycleConfig[0].mustStartAtOrAfter = 0;
            _cycleConfig[0].data = _data;
            _cycleConfig[0].metadata = _metadata;
            _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
            _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

            // First project for fee collection
            _controller.launchProjectFor({
                owner: address(420), // random
                projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
                configurations: _cycleConfig, // use the same cycle configs
                terminals: _terminals, // set terminals where fees will be received
                memo: ""
            });

            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: _projectMetadata,
                configurations: _cycleConfig,
                terminals: _terminals,
                memo: ""
            });
        }

        // Set the fee collecting terminal's ETH accounting context.
        _terminal.setTokenAccountingContextFor({
            projectId: _FEE_PROJECT_ID,
            token: JBTokens.ETH,
            decimals: _ETH_DECIMALS,
            currency: uint32(JBCurrencies.ETH)
        });

        // Set the test project's terminal's ETH accounting context.
        _terminal.setTokenAccountingContextFor({
            projectId: _projectId,
            token: JBTokens.ETH,
            decimals: _ETH_DECIMALS,
            currency: uint32(JBCurrencies.ETH)
        });

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId, 
            amount: _ethPayAmount, 
            token: JBTokens.ETH,
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount);

        // Revert if there's no allowance.
        if (_ethOverflowAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        // Revert if there's no overflow, or if too much is being withdrawn.
        } else if (_ethOverflowAllowance + _ethDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary allowance of overflow.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethOverflowAllowance,
            currency: JBCurrencies.ETH,
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary), // Beneficiary
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's balance;
        uint256 _beneficiaryBalance;

        // Check the collected balance if one is expected.
        if (_ethOverflowAllowance + _ethDistributionLimit <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryBalance = PRBMath.mulDiv(_ethOverflowAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
            assertEq(_beneficiary.balance, _beneficiaryBalance);
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethOverflowAllowance);

            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), _ethOverflowAllowance - _beneficiaryBalance);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv(_ethOverflowAllowance - _beneficiaryBalance, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        } else {
            // Set the eth overflow allowance value to 0 if it wasnt used.
            _ethOverflowAllowance = 0;
        }

        // Revert if the distribution limit is greater than the balance.
        if (_ethDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));

        // Revert if there's no distribution limit.
        } else if (_ethDistributionLimit == 0) {
            vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
        }

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _ethDistributionLimit,
            currency: JBCurrencies.ETH,
            token: JBTokens.ETH,
            minReturnedTokens: 0
        });

        uint256 _projectOwnerBalance;  

        // Check the collected distribution if one is expected.
        if (_ethDistributionLimit <= _ethPayAmount && _ethDistributionLimit != 0) {
            // Make sure the project owner received the distributed funds.
            _projectOwnerBalance = (_ethDistributionLimit * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);
            assertEq(_projectOwner.balance, _projectOwnerBalance);
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethOverflowAllowance - _ethDistributionLimit);

            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance));
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance);

            // Make sure the project owner got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv((_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance), _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        }

        // Redeem ETH from the overflow using all of the _beneficiary's tokens.
        vm.prank(_beneficiary);
        _terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            tokenCount: _beneficiaryTokenBalance,
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            metadata: new bytes(0)
        });

        // Make sure the beneficiary doesn't have tokens left.
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), 0);

        // Check for a new beneficiary balance if one is expected.
        if (_ethPayAmount > _ethOverflowAllowance + _ethDistributionLimit) {
            // Get the expected amount reclaimed.
            uint256 _reclaimAmount = (PRBMath.mulDiv(
                PRBMath.mulDiv(_ethPayAmount - _ethOverflowAllowance - _ethDistributionLimit, _beneficiaryTokenBalance, PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)),
                _metadata.redemptionRate +
                PRBMath.mulDiv(
                    _beneficiaryTokenBalance,
                    JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                    PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
                ),
                JBConstants.MAX_REDEMPTION_RATE
            ));
            // Calculate the fee from the redemption.
            uint256 _feeAmount = _reclaimAmount - _reclaimAmount * JBConstants.MAX_FEE / (_terminal.fee() + JBConstants.MAX_FEE);
            assertEq(_beneficiary.balance, _beneficiaryBalance + _reclaimAmount - _feeAmount);
            
            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance) + _feeAmount);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance - (_reclaimAmount - _feeAmount));

            // Make sure the project owner got the expected number of tokens from the fee.
            assertEq(_tokenStore.balanceOf(_beneficiary, _FEE_PROJECT_ID), PRBMath.mulDiv(_feeAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        }
    }

    function testFuzzETHAllowanceWithRevertingFeeProject(uint232 _ethOverflowAllowance, uint232 _ethDistributionLimit, uint256 _ethPayAmount, bool _feeProjectAcceptsToken) public {
        // Make sure the amount of eth to pay is bounded. 
        _ethPayAmount = bound(_ethPayAmount, 0, 1000000 * 10**_ETH_DECIMALS);

        // Make sure the values don't overflow the registry.
        unchecked {
            vm.assume(_ethOverflowAllowance + _ethDistributionLimit >= _ethOverflowAllowance && _ethOverflowAllowance + _ethDistributionLimit >= _ethDistributionLimit);
        }

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        {
            // Specify a distribution limit.
            JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
            _distributionLimits[0] = JBCurrencyAmount({
                value: _ethDistributionLimit,
                currency: JBCurrencies.ETH
            });  

            // Specify an overflow allowance.
            JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
            _overflowAllowances[0] = JBCurrencyAmount({
                value: _ethOverflowAllowance,
                currency: JBCurrencies.ETH
            });

            _fundAccessConstraints[0] =
                JBFundAccessConstraints({
                    terminal: _terminal,
                    token: JBTokens.ETH,
                    distributionLimits: _distributionLimits,
                    overflowAllowances: _overflowAllowances
                });
        }

        // Keep references to the projects.
        uint256 _projectId;

        {
            // First project for fee collection
            _controller.launchProjectFor({
                owner: address(420), // random
                projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
                configurations: new JBFundingCycleConfiguration[](0), // No cycle config will force revert when paid.
                terminals: _terminals, // set terminals where fees will be received
                memo: ""
            });

            // Package up the configuration info.
            JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
            _cycleConfig[0].mustStartAtOrAfter = 0;
            _cycleConfig[0].data = _data;
            _cycleConfig[0].metadata = _metadata;
            _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
            _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: _projectMetadata,
                configurations: _cycleConfig,
                terminals: _terminals,
                memo: ""
            });
        }

        // Set the fee collecting terminal's ETH accounting context if the test calls for doing so.
        if (_feeProjectAcceptsToken)
            _terminal.setTokenAccountingContextFor({
                projectId: _FEE_PROJECT_ID,
                token: JBTokens.ETH,
                decimals: _ETH_DECIMALS,
                currency: uint32(JBCurrencies.ETH)
            });

        // Set the test project's terminal's ETH accounting context.
        _terminal.setTokenAccountingContextFor({
            projectId: _projectId,
            token: JBTokens.ETH,
            decimals: _ETH_DECIMALS,
            currency: uint32(JBCurrencies.ETH)
        });

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId, 
            amount: _ethPayAmount, 
            token: JBTokens.ETH, 
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount);

        // Revert if there's no allowance.
        if (_ethOverflowAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        // Revert if there's no overflow, or if too much is being withdrawn.
        } else if (_ethOverflowAllowance + _ethDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary allowance of overflow.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethOverflowAllowance,
            currency: JBCurrencies.ETH,
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary), // Beneficiary
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's balance;
        uint256 _beneficiaryBalance;

        // Check the collected balance if one is expected.
        if (_ethOverflowAllowance + _ethDistributionLimit <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryBalance = PRBMath.mulDiv(_ethOverflowAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
            assertEq(_beneficiary.balance, _beneficiaryBalance);
            // Make sure the fee stays in the treasury.
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryBalance);

            // Make sure the fee was not taken.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), 0);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance);

            // Make sure the beneficiary got no tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), 0);
        } else {
            // Set the eth overflow allowance value to 0 if it wasnt used.
            _ethOverflowAllowance = 0;
        }

        // Revert if the distribution limit is greater than the balance.
        if (_ethDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));

        // Revert if there's no distribution limit.
        } else if (_ethDistributionLimit == 0) {
            vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
        }

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _ethDistributionLimit,
            currency: JBCurrencies.ETH,
            token: JBTokens.ETH, 
            minReturnedTokens: 0
        });

        uint256 _projectOwnerBalance;  

        // Check the collected distribution if one is expected.
        if (_ethDistributionLimit <= _ethPayAmount && _ethDistributionLimit != 0) {
            // Make sure the project owner received the distributed funds.
            _projectOwnerBalance = (_ethDistributionLimit * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);
            assertEq(_projectOwner.balance, _projectOwnerBalance);
            // Make sure the fee stays in the treasury.
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance);

            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), 0);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance);

            // Make sure the project owner got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), 0);
        }

        // Redeem ETH from the overflow using all of the _beneficiary's tokens.
        vm.prank(_beneficiary);
        _terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            tokenCount: _beneficiaryTokenBalance,
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            metadata: new bytes(0)
        });

        // Make sure the beneficiary doesn't have tokens left.
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), 0);

        // Check for a new beneficiary balance if one is expected.
        if (_ethPayAmount > _ethOverflowAllowance + _ethDistributionLimit) {
            // Get the expected amount reclaimed.
            uint256 _reclaimAmount = (PRBMath.mulDiv(
                PRBMath.mulDiv(_ethPayAmount - _beneficiaryBalance - _projectOwnerBalance, _beneficiaryTokenBalance, PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)),
                _metadata.redemptionRate +
                PRBMath.mulDiv(
                    _beneficiaryTokenBalance,
                    JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                    PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
                ),
                JBConstants.MAX_REDEMPTION_RATE
            ));

            // Calculate the fee from the redemption.
            uint256 _feeAmount = _reclaimAmount - _reclaimAmount * JBConstants.MAX_FEE / (_terminal.fee() + JBConstants.MAX_FEE);
            assertEq(_beneficiary.balance, _beneficiaryBalance + _reclaimAmount - _feeAmount);
            // Make sure the fee stays in the treasury.
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance - (_reclaimAmount - _feeAmount));
            
            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), 0);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance - (_reclaimAmount - _feeAmount));

            // Make sure the project owner got the expected number of tokens from the fee.
            assertEq(_tokenStore.balanceOf(_beneficiary, _FEE_PROJECT_ID), 0);
        }
    }

    function testFuzzETHAllowanceForTheFeeProject(uint232 _ethOverflowAllowance, uint232 _ethDistributionLimit, uint256 _ethPayAmount) public {
        // Make sure the amount of eth to pay is bounded. 
        _ethPayAmount = bound(_ethPayAmount, 0, 1000000 * 10**_ETH_DECIMALS);

        // Make sure the values don't overflow the registry.
        unchecked {
            vm.assume(_ethOverflowAllowance + _ethDistributionLimit >= _ethOverflowAllowance && _ethOverflowAllowance + _ethDistributionLimit >= _ethDistributionLimit);
        }

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        {
            // Specify a distribution limit.
            JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
            _distributionLimits[0] = JBCurrencyAmount({
                value: _ethDistributionLimit,
                currency: JBCurrencies.ETH
            });  

            // Specify an overflow allowance.
            JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
            _overflowAllowances[0] = JBCurrencyAmount({
                value: _ethOverflowAllowance,
                currency: JBCurrencies.ETH 
            });

            _fundAccessConstraints[0] =
                JBFundAccessConstraints({
                    terminal: _terminal,
                    token: JBTokens.ETH,
                    distributionLimits: _distributionLimits,
                    overflowAllowances: _overflowAllowances
                });
        }

        // Keep references to the projects.
        uint256 _projectId;

        {
            // Package up the configuration info.
            JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
            _cycleConfig[0].mustStartAtOrAfter = 0;
            _cycleConfig[0].data = _data;
            _cycleConfig[0].metadata = _metadata;
            _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
            _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;
            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: _projectMetadata,
                configurations: _cycleConfig,
                terminals: _terminals,
                memo: ""
            });
        }

        // Set the test project's terminal's ETH accounting context.
        _terminal.setTokenAccountingContextFor({
            projectId: _projectId,
            token: JBTokens.ETH,
            decimals: _ETH_DECIMALS,
            currency: uint32(JBCurrencies.ETH)
        });

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId, 
            amount: _ethPayAmount, 
            token: JBTokens.ETH,
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount);

        // Revert if there's no allowance.
        if (_ethOverflowAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        // Revert if there's no overflow, or if too much is being withdrawn.
        } else if (_ethOverflowAllowance + _ethDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary allowance of overflow.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethOverflowAllowance,
            currency: JBCurrencies.ETH,
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary), // Beneficiary
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's balance;
        uint256 _beneficiaryBalance;

        // Check the collected balance if one is expected.
        if (_ethOverflowAllowance + _ethDistributionLimit <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryBalance = PRBMath.mulDiv(_ethOverflowAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
            assertEq(_beneficiary.balance, _beneficiaryBalance);
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryBalance);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv(_ethOverflowAllowance - _beneficiaryBalance, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        } else {
            // Set the eth overflow allowance value to 0 if it wasnt used.
            _ethOverflowAllowance = 0;
        }

        // Revert if the distribution limit is greater than the balance.
        if (_ethDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));

        // Revert if there's no distribution limit.
        } else if (_ethDistributionLimit == 0) {
            vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
        }

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _ethDistributionLimit,
            currency: JBCurrencies.ETH,
            token: JBTokens.ETH,
            minReturnedTokens: 0
        });

        uint256 _projectOwnerBalance;  

        // Check the collected distribution if one is expected.
        if (_ethDistributionLimit <= _ethPayAmount && _ethDistributionLimit != 0) {
            // Make sure the project owner received the distributed funds.
            _projectOwnerBalance = (_ethDistributionLimit * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);
            assertEq(_projectOwner.balance, _projectOwnerBalance);
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance);

            // Make sure the project owner got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv((_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance), _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        }

        // Redeem ETH from the overflow using all of the _beneficiary's tokens.
        vm.prank(_beneficiary);
        _terminal.redeemTokensOf({
            holder: _beneficiary,
            projectId: _projectId,
            tokenCount: _beneficiaryTokenBalance,
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary),
            metadata: new bytes(0)
        });

        // Check for a new beneficiary balance if one is expected.
        if (_ethPayAmount > _ethOverflowAllowance + _ethDistributionLimit) {
            
            // Keep a reference to the total amount paid, including from fees.
            uint256 _totalPaid = _ethPayAmount + (_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance);

            // Get the expected amount reclaimed.
            uint256 _reclaimAmount = (PRBMath.mulDiv(
                PRBMath.mulDiv(_ethPayAmount - _beneficiaryBalance - _projectOwnerBalance, _beneficiaryTokenBalance, PRBMath.mulDiv(_totalPaid, _data.weight, 10 ** _ETH_DECIMALS)),
                _metadata.redemptionRate +
                PRBMath.mulDiv(
                    _beneficiaryTokenBalance,
                    JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                    PRBMath.mulDiv(_totalPaid, _data.weight, 10 ** _ETH_DECIMALS)
                ),
                JBConstants.MAX_REDEMPTION_RATE
            ));
            // Calculate the fee from the redemption.
            uint256 _feeAmount = _reclaimAmount - _reclaimAmount * JBConstants.MAX_FEE / (_terminal.fee() + JBConstants.MAX_FEE);

            // Make sure the beneficiary has token from the fee just paid.
            assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), PRBMath.mulDiv(_feeAmount, _data.weight, 10 ** _ETH_DECIMALS ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);

            // Make sure the beneficiary received the funds.
            assertEq(_beneficiary.balance, _beneficiaryBalance + _reclaimAmount - _feeAmount);

            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance - (_reclaimAmount - _feeAmount));
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance - (_reclaimAmount - _feeAmount));
        }
    }

    function testFuzzMultiCurrencyAllowance(uint232 _ethOverflowAllowance, uint232 _ethDistributionLimit, uint256 _ethPayAmount, uint232 _usdcOverflowAllowance, uint232 _usdcDistributionLimit, uint256 _usdcPayAmount) public {
        // Make sure the amount of eth to pay is bounded. 
        _ethPayAmount = bound(_ethPayAmount, 0, 1000000 * 10**_ETH_DECIMALS);
        _usdcPayAmount = bound(_usdcPayAmount, 0, 1000000 * 10**_USDC_DECIMALS);

        // Make sure the values don't overflow the registry.
        unchecked {
            vm.assume(_ethOverflowAllowance + _ethDistributionLimit >= _ethOverflowAllowance && _ethOverflowAllowance + _ethDistributionLimit >= _ethDistributionLimit);
            vm.assume(_usdcOverflowAllowance + _usdcDistributionLimit >= _usdcOverflowAllowance && _usdcOverflowAllowance + _usdcDistributionLimit >= _usdcDistributionLimit);
        }

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](2);
        {
            // Specify a distribution limit.
            JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](2);
            _distributionLimits[0] = JBCurrencyAmount({
                value: _ethDistributionLimit,
                currency: JBCurrencies.ETH
            });  
            _distributionLimits[1] = JBCurrencyAmount({
                value: _ethDistributionLimit,
                currency: JBCurrencies.USD
            });  

            // Specify an overflow allowance.
            JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](2);
            _overflowAllowances[0] = JBCurrencyAmount({
                value: _ethOverflowAllowance,
                currency: JBCurrencies.ETH 
            });
            _overflowAllowances[1] = JBCurrencyAmount({
                value: _ethOverflowAllowance,
                currency: JBCurrencies.USD
            });

            _fundAccessConstraints[0] =
                JBFundAccessConstraints({
                    terminal: _terminal,
                    token: JBTokens.ETH,
                    distributionLimits: _distributionLimits,
                    overflowAllowances: _overflowAllowances
                });
            _fundAccessConstraints[1] =
                JBFundAccessConstraints({
                    terminal: _terminal,
                    token: address(_usdcToken),
                    distributionLimits: _distributionLimits,
                    overflowAllowances: _overflowAllowances
                });
        }

        // Keep references to the projects.
        uint256 _projectId;

        {
            // Package up the configuration info.
            JBFundingCycleConfiguration[] memory _cycleConfig = new JBFundingCycleConfiguration[](1);
            _cycleConfig[0].mustStartAtOrAfter = 0;
            _cycleConfig[0].data = _data;
            _cycleConfig[0].metadata = _metadata;
            _cycleConfig[0].groupedSplits = new JBGroupedSplits[](0);
            _cycleConfig[0].fundAccessConstraints = _fundAccessConstraints;

            // First project for fee collection
            _controller.launchProjectFor({
                owner: address(420), // random
                projectMetadata: JBProjectMetadata({content: "whatever", domain: 0}),
                configurations: _cycleConfig, // use the same cycle configs
                terminals: _terminals, // set terminals where fees will be received
                memo: ""
            });

            // Create the project to test.
            _projectId = _controller.launchProjectFor({
                owner: _projectOwner,
                projectMetadata: _projectMetadata,
                configurations: _cycleConfig,
                terminals: _terminals,
                memo: ""
            });
        }

        // Set the fee collecting terminal's ETH accounting context.
        _terminal.setTokenAccountingContextFor({
            projectId: _FEE_PROJECT_ID,
            token: JBTokens.ETH,
            decimals: _ETH_DECIMALS,
            currency: uint32(JBCurrencies.ETH)
        });

        // Set the test project's terminal's ETH accounting context.
        _terminal.setTokenAccountingContextFor({
            projectId: _projectId,
            token: JBTokens.ETH,
            decimals: _ETH_DECIMALS,
            currency: uint32(JBCurrencies.ETH)
        });

        // Set the fee collecting terminal's usdc accounting context.
        _terminal.setTokenAccountingContextFor({
            projectId: _FEE_PROJECT_ID,
            token: address(_usdcToken),
            decimals: _USDC_DECIMALS,
            currency: uint32(JBCurrencies.USD)
        });

        // Set the test project's terminal's ETH accounting context.
        _terminal.setTokenAccountingContextFor({
            projectId: _projectId,
            token: address(_usdcToken),
            decimals: _USDC_DECIMALS,
            currency: uint32(JBCurrencies.USD)
        });

        // Add a price feed to convert from ETH to USD currencies.
        {
            vm.startPrank(_projectOwner);
            MockPriceFeed _priceFeedEthUsd = new MockPriceFeed(_USDC_PRICE_PER_ETH, _PRICE_FEED_DECIMALS);
            vm.label(address(_priceFeedEthUsd), "MockPrice Feed ETH-USDC");

            _prices.addFeedFor({
                projectId: _projectId,
                currency: JBCurrencies.USD, 
                base: JBCurrencies.ETH, 
                priceFeed: _priceFeedEthUsd
            });

            vm.stopPrank();
        }

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId, 
            amount: _ethPayAmount, 
            token: JBTokens.ETH,
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens from the ETH payment.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS), JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate, JBConstants.MAX_RESERVED_RATE);
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

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
            metadata: new bytes(0)
        });

        {
            // Convert the usd amount to an eth amount, byway of the current weight used for issuance.
            uint256 _usdWeightedPayAmountConvertedToEth = PRBMath.mulDiv(_usdcPayAmount, _data.weight, PRBMath.mulDiv(_USDC_PRICE_PER_ETH, 10**_USDC_DECIMALS, 10**_PRICE_FEED_DECIMALS));

            // Make sure the beneficiary got the expected number of tokens from the USDC payment.
            _beneficiaryTokenBalance += PRBMath.mulDiv(_usdWeightedPayAmountConvertedToEth, JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate, JBConstants.MAX_RESERVED_RATE);
            assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);
        }

        // // Make sure the terminal holds the full ETH balance.
        // assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount);

        // // Revert if there's no allowance.
        // if (_ethOverflowAllowance == 0) {
        //     vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        // // Revert if there's no overflow, or if too much is being withdrawn.
        // } else if (_ethOverflowAllowance + _ethDistributionLimit > _ethPayAmount) {
        //     vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        // }

        // // Use the full discretionary allowance of overflow.
        // vm.prank(_projectOwner);
        // _terminal.useAllowanceOf({
        //     projectId: _projectId,
        //     amount: _ethOverflowAllowance,
        //     currency: JBCurrencies.ETH,
        //     token: JBTokens.ETH,
        //     minReturnedTokens: 0,
        //     beneficiary: payable(_beneficiary), // Beneficiary
        //     memo: "MEMO"
        // });

        // // Keep a reference to the beneficiary's balance;
        // uint256 _beneficiaryBalance;

        // // Check the collected balance if one is expected.
        // if (_ethOverflowAllowance + _ethDistributionLimit <= _ethPayAmount) {
        //     // Make sure the beneficiary received the funds and that they are no longer in the terminal.
        //     _beneficiaryBalance = PRBMath.mulDiv(_ethOverflowAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
        //     assertEq(_beneficiary.balance, _beneficiaryBalance);
        //     assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethOverflowAllowance);

        //     // Make sure the fee was paid correctly.
        //     assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), _ethOverflowAllowance - _beneficiaryBalance);
        //     assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance);

        //     // Make sure the beneficiary got the expected number of tokens.
        //     assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv(_ethOverflowAllowance - _beneficiaryBalance, _data.weight, 10 ** _WEIGHT_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        // } else {
        //     // Set the eth overflow allowance value to 0 if it wasnt used.
        //     _ethOverflowAllowance = 0;
        // }

        // // Revert if the distribution limit is greater than the balance.
        // if (_ethDistributionLimit > _ethPayAmount) {
        //     vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));

        // // Revert if there's no distribution limit.
        // } else if (_ethDistributionLimit == 0) {
        //     vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
        // }

        // // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        // _terminal.distributePayoutsOf({
        //     projectId: _projectId,
        //     amount: _ethDistributionLimit,
        //     currency: JBCurrencies.ETH,
        //     token: JBTokens.ETH,
        //     minReturnedTokens: 0
        // });

        // uint256 _projectOwnerBalance;  

        // // Check the collected distribution if one is expected.
        // if (_ethDistributionLimit <= _ethPayAmount && _ethDistributionLimit != 0) {
        //     // Make sure the project owner received the distributed funds.
        //     _projectOwnerBalance = (_ethDistributionLimit * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);
        //     assertEq(_projectOwner.balance, _projectOwnerBalance);
        //     assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethOverflowAllowance - _ethDistributionLimit);

        //     // Make sure the fee was paid correctly.
        //     assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance));
        //     assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance);

        //     // Make sure the project owner got the expected number of tokens.
        //     assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv((_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance), _data.weight, 10 ** _WEIGHT_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        // }

        // // Redeem ETH from the overflow using all of the _beneficiary's tokens.
        // vm.prank(_beneficiary);
        // _terminal.redeemTokensOf({
        //     holder: _beneficiary,
        //     projectId: _projectId,
        //     tokenCount: _beneficiaryTokenBalance,
        //     token: JBTokens.ETH,
        //     minReturnedTokens: 0,
        //     beneficiary: payable(_beneficiary),
        //     metadata: new bytes(0)
        // });

        // // Make sure the beneficiary doesn't have tokens left.
        // assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), 0);

        // // Check for a new beneficiary balance if one is expected.
        // if (_ethPayAmount > _ethOverflowAllowance + _ethDistributionLimit) {
        //     // Get the expected amount reclaimed.
        //     uint256 _reclaimAmount = (PRBMath.mulDiv(
        //         PRBMath.mulDiv(_ethPayAmount - _ethOverflowAllowance - _ethDistributionLimit, _beneficiaryTokenBalance, PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _DATA_WEIGHT)),
        //         _metadata.redemptionRate +
        //         PRBMath.mulDiv(
        //             _beneficiaryTokenBalance,
        //             JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
        //             PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _WEIGHT_DECIMALS)
        //         ),
        //         JBConstants.MAX_REDEMPTION_RATE
        //     ));
        //     // Calculate the fee from the redemption.
        //     uint256 _feeAmount = _reclaimAmount - _reclaimAmount * JBConstants.MAX_FEE / (_terminal.fee() + JBConstants.MAX_FEE);
        //     assertEq(_beneficiary.balance, _beneficiaryBalance + _reclaimAmount - _feeAmount);
            
        //     // Make sure the fee was paid correctly.
        //     assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethOverflowAllowance - _beneficiaryBalance) + (_ethDistributionLimit - _projectOwnerBalance) + _feeAmount);
        //     assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryBalance - _projectOwnerBalance - (_reclaimAmount - _feeAmount));

        //     // Make sure the project owner got the expected number of tokens from the fee.
        //     assertEq(_tokenStore.balanceOf(_beneficiary, _FEE_PROJECT_ID), PRBMath.mulDiv(_feeAmount, _data.weight, 10 ** _WEIGHT_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        // }
    }
}