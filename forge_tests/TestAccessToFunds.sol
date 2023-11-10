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
    uint8 private constant _ETH_DECIMALS = 18; // FIXED
    uint8 private constant _PRICE_FEED_DECIMALS = 10; 
    uint256 private constant _USD_PRICE_PER_ETH = 2000 * 10**_PRICE_FEED_DECIMALS; // 2000 USDC == 1 ETH
    
    IJBController3_1 private _controller;
    IJBPrices private _prices;
    IJBPayoutRedemptionTerminal private _terminal; 
    IJBTokenStore private _tokenStore;
    address private _multisig;
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
        _multisig = multisig();
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
            baseCurrency: uint24(uint160(JBTokens.ETH)),
            pausePay: false,
            pauseDistributions: false,
            pauseRedeem: false,
            pauseBurn: false,
            allowMinting: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            preferClaimedTokenOverride: false,
            useTotalOverflowForRedemptions: true,
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
        uint256 _ethCurrencyDistributionLimit = 10 * 10**_ETH_DECIMALS;
        uint256 _ethCurrencyOverflowAllowance = 5 * 10**_ETH_DECIMALS;

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        {
            // Specify a distribution limit.
            JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
            _distributionLimits[0] = JBCurrencyAmount({
                value: _ethCurrencyDistributionLimit,
                currency: uint24(uint160(JBTokens.ETH))
            });  

            // Specify an overflow allowance.
            JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
            _overflowAllowances[0] = JBCurrencyAmount({
                value: _ethCurrencyOverflowAllowance,
                currency: uint24(uint160(JBTokens.ETH))
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
        _terminal.setAccountingContextFor({
            projectId: _FEE_PROJECT_ID,
            token: JBTokens.ETH,
            standard: JBTokenStandards.NATIVE
        });

        // Set the test project's terminal's ETH accounting context.
        _terminal.setAccountingContextFor({
            projectId: _projectId,
            token: JBTokens.ETH,
            standard: JBTokenStandards.NATIVE
        });

        // Get a reference to the amount being paid, such that the distribution limit is met with two times the overflow than is allowed to be withdrawn.
        uint256 _ethPayAmount = _ethCurrencyDistributionLimit + (2 * _ethCurrencyOverflowAllowance);
        
        // Pay the project such that the _beneficiary receives project tokens.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId, 
            amount: _ethPayAmount, 
            token: JBTokens.ETH, 
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            memo: "",
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
            amount: _ethCurrencyOverflowAllowance,
            currency: uint24(uint160(JBTokens.ETH)),
            token: JBTokens.ETH,
            minReturnedTokens: 0, 
            beneficiary: payable(_beneficiary),
            memo: "MEMO"
        });
        
        // Make sure the beneficiary received the funds and that they are no longer in the terminal.
        uint256 _beneficiaryEthBalance = PRBMath.mulDiv(_ethCurrencyOverflowAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
        assertEq(_beneficiary.balance, _beneficiaryEthBalance);
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethCurrencyOverflowAllowance);

        // Make sure the fee was paid correctly.
        assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), _ethCurrencyOverflowAllowance - _beneficiaryEthBalance);
        assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

        // Make sure the project owner got the expected number of tokens.
        assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv(_ethCurrencyOverflowAllowance - _beneficiaryEthBalance, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _ethCurrencyDistributionLimit,
            currency: uint24(uint160(JBTokens.ETH)),
            token: JBTokens.ETH,
            minReturnedTokens: 0
        });

        // Make sure the project owner received the distributed funds.
        uint256 _projectOwnerEthBalance = (_ethCurrencyDistributionLimit * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);

        // Make sure the project owner received the full amount.
        assertEq(_projectOwner.balance, _projectOwnerEthBalance);
        
        // Make sure the fee was paid correctly.
        assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethCurrencyOverflowAllowance - _beneficiaryEthBalance) + (_ethCurrencyDistributionLimit - _projectOwnerEthBalance));
        assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance);

        // Make sure the project owner got the expected number of tokens.
        assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv((_ethCurrencyOverflowAllowance - _beneficiaryEthBalance) + (_ethCurrencyDistributionLimit - _projectOwnerEthBalance), _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);

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
        uint256 _ethReclaimAmount = PRBMath.mulDiv(
            PRBMath.mulDiv(_ethPayAmount - _ethCurrencyOverflowAllowance - _ethCurrencyDistributionLimit, _beneficiaryTokenBalance, PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)),
            _metadata.redemptionRate +
            PRBMath.mulDiv(
                _beneficiaryTokenBalance,
                JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
            ),
            JBConstants.MAX_REDEMPTION_RATE
        );

        // Calculate the fee from the redemption.
        uint256 _feeAmount = _ethReclaimAmount - _ethReclaimAmount * JBConstants.MAX_FEE / (_terminal.fee() + JBConstants.MAX_FEE);
        assertEq(_beneficiary.balance, _beneficiaryEthBalance + _ethReclaimAmount - _feeAmount);
        
        // // Make sure the fee was paid correctly.
        assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethCurrencyOverflowAllowance - _beneficiaryEthBalance) + (_ethCurrencyDistributionLimit - _projectOwnerEthBalance) + _feeAmount);
        assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance - (_ethReclaimAmount - _feeAmount));

        // Make sure the project owner got the expected number of tokens from the fee.
        assertEq(_tokenStore.balanceOf(_beneficiary, _FEE_PROJECT_ID), PRBMath.mulDiv(_feeAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
    }

    function testFuzzETHAllowance(uint232 _ethCurrencyOverflowAllowance, uint232 _ethCurrencyDistributionLimit, uint256 _ethPayAmount) public {
        // Make sure the amount of eth to pay is bounded. 
        _ethPayAmount = bound(_ethPayAmount, 0, 1000000 * 10**_ETH_DECIMALS);

        // Make sure the values don't overflow the registry.
        unchecked {
            vm.assume(_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit >= _ethCurrencyOverflowAllowance && _ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit >= _ethCurrencyDistributionLimit);
        }

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        {
            // Specify a distribution limit.
            JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
            _distributionLimits[0] = JBCurrencyAmount({
                value: _ethCurrencyDistributionLimit,
                currency: uint24(uint160(JBTokens.ETH))
            });  

            // Specify an overflow allowance.
            JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
            _overflowAllowances[0] = JBCurrencyAmount({
                value: _ethCurrencyOverflowAllowance,
                currency: uint24(uint160(JBTokens.ETH)) 
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
        _terminal.setAccountingContextFor({
            projectId: _FEE_PROJECT_ID,
            token: JBTokens.ETH,
            standard: JBTokenStandards.NATIVE
        });

        // Set the test project's terminal's ETH accounting context.
        _terminal.setAccountingContextFor({
            projectId: _projectId,
            token: JBTokens.ETH,
            standard: JBTokenStandards.NATIVE
        });

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId, 
            amount: _ethPayAmount, 
            token: JBTokens.ETH,
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount);

        // Revert if there's no allowance.
        if (_ethCurrencyOverflowAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        // Revert if there's no overflow, or if too much is being withdrawn.
        } else if (_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary allowance of overflow.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethCurrencyOverflowAllowance,
            currency: uint24(uint160(JBTokens.ETH)),
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary), 
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's balance;
        uint256 _beneficiaryEthBalance;

        // Check the collected balance if one is expected.
        if (_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance = PRBMath.mulDiv(_ethCurrencyOverflowAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethCurrencyOverflowAllowance);

            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), _ethCurrencyOverflowAllowance - _beneficiaryEthBalance);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv(_ethCurrencyOverflowAllowance - _beneficiaryEthBalance, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        } else {
            // Set the eth overflow allowance value to 0 if it wasnt used.
            _ethCurrencyOverflowAllowance = 0;
        }

        // Revert if the distribution limit is greater than the balance.
        if (_ethCurrencyDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));

        // Revert if there's no distribution limit.
        } else if (_ethCurrencyDistributionLimit == 0) {
            vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
        }

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _ethCurrencyDistributionLimit,
            currency: uint24(uint160(JBTokens.ETH)),
            token: JBTokens.ETH,
            minReturnedTokens: 0
        });

        uint256 _projectOwnerEthBalance;  

        // Check the collected distribution if one is expected.
        if (_ethCurrencyDistributionLimit <= _ethPayAmount && _ethCurrencyDistributionLimit != 0) {
            // Make sure the project owner received the distributed funds.
            _projectOwnerEthBalance = (_ethCurrencyDistributionLimit * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);
            assertEq(_projectOwner.balance, _projectOwnerEthBalance);
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethCurrencyOverflowAllowance - _ethCurrencyDistributionLimit);

            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethCurrencyOverflowAllowance - _beneficiaryEthBalance) + (_ethCurrencyDistributionLimit - _projectOwnerEthBalance));
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance);

            // Make sure the project owner got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv((_ethCurrencyOverflowAllowance - _beneficiaryEthBalance) + (_ethCurrencyDistributionLimit - _projectOwnerEthBalance), _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
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
        if (_ethPayAmount > _ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit) {
            // Get the expected amount reclaimed.
            uint256 _ethReclaimAmount = PRBMath.mulDiv(
                PRBMath.mulDiv(_ethPayAmount - _ethCurrencyOverflowAllowance - _ethCurrencyDistributionLimit, _beneficiaryTokenBalance, PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)),
                _metadata.redemptionRate +
                PRBMath.mulDiv(
                    _beneficiaryTokenBalance,
                    JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                    PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
                ),
                JBConstants.MAX_REDEMPTION_RATE
            );
            // Calculate the fee from the redemption.
            uint256 _feeAmount = _ethReclaimAmount - _ethReclaimAmount * JBConstants.MAX_FEE / (_terminal.fee() + JBConstants.MAX_FEE);
            assertEq(_beneficiary.balance, _beneficiaryEthBalance + _ethReclaimAmount - _feeAmount);
            
            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethCurrencyOverflowAllowance - _beneficiaryEthBalance) + (_ethCurrencyDistributionLimit - _projectOwnerEthBalance) + _feeAmount);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance - (_ethReclaimAmount - _feeAmount));

            // Make sure the project owner got the expected number of tokens from the fee.
            assertEq(_tokenStore.balanceOf(_beneficiary, _FEE_PROJECT_ID), PRBMath.mulDiv(_feeAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        }
    }

    function testFuzzETHAllowanceWithRevertingFeeProject(uint232 _ethCurrencyOverflowAllowance, uint232 _ethCurrencyDistributionLimit, uint256 _ethPayAmount, bool _feeProjectAcceptsToken) public {
        // Make sure the amount of eth to pay is bounded. 
        _ethPayAmount = bound(_ethPayAmount, 0, 1000000 * 10**_ETH_DECIMALS);

        // Make sure the values don't overflow the registry.
        unchecked {
            vm.assume(_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit >= _ethCurrencyOverflowAllowance && _ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit >= _ethCurrencyDistributionLimit);
        }

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        {
            // Specify a distribution limit.
            JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
            _distributionLimits[0] = JBCurrencyAmount({
                value: _ethCurrencyDistributionLimit,
                currency: uint24(uint160(JBTokens.ETH))
            });  

            // Specify an overflow allowance.
            JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
            _overflowAllowances[0] = JBCurrencyAmount({
                value: _ethCurrencyOverflowAllowance,
                currency: uint24(uint160(JBTokens.ETH))
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
            _terminal.setAccountingContextFor({
                projectId: _FEE_PROJECT_ID,
                token: JBTokens.ETH,
                standard: JBTokenStandards.NATIVE
            });

        // Set the test project's terminal's ETH accounting context.
        _terminal.setAccountingContextFor({
            projectId: _projectId,
            token: JBTokens.ETH,
            standard: JBTokenStandards.NATIVE
        });

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId, 
            amount: _ethPayAmount, 
            token: JBTokens.ETH, 
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount);

        // Revert if there's no allowance.
        if (_ethCurrencyOverflowAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        // Revert if there's no overflow, or if too much is being withdrawn.
        } else if (_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary allowance of overflow.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethCurrencyOverflowAllowance,
            currency: uint24(uint160(JBTokens.ETH)),
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary), 
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's balance;
        uint256 _beneficiaryEthBalance;

        // Check the collected balance if one is expected.
        if (_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance = PRBMath.mulDiv(_ethCurrencyOverflowAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            // Make sure the fee stays in the treasury.
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the fee was not taken.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), 0);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got no tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), 0);
        } else {
            // Set the eth overflow allowance value to 0 if it wasnt used.
            _ethCurrencyOverflowAllowance = 0;
        }

        // Revert if the distribution limit is greater than the balance.
        if (_ethCurrencyDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));

        // Revert if there's no distribution limit.
        } else if (_ethCurrencyDistributionLimit == 0) {
            vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
        }

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _ethCurrencyDistributionLimit,
            currency: uint24(uint160(JBTokens.ETH)),
            token: JBTokens.ETH, 
            minReturnedTokens: 0
        });

        uint256 _projectOwnerEthBalance;  

        // Check the collected distribution if one is expected.
        if (_ethCurrencyDistributionLimit <= _ethPayAmount && _ethCurrencyDistributionLimit != 0) {
            // Make sure the project owner received the distributed funds.
            _projectOwnerEthBalance = (_ethCurrencyDistributionLimit * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);
            assertEq(_projectOwner.balance, _projectOwnerEthBalance);
            // Make sure the fee stays in the treasury.
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance);

            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), 0);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance);

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
        if (_ethPayAmount > _ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit) {
            // Get the expected amount reclaimed.
            uint256 _ethReclaimAmount = PRBMath.mulDiv(
                PRBMath.mulDiv(_ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance, _beneficiaryTokenBalance, PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)),
                _metadata.redemptionRate +
                PRBMath.mulDiv(
                    _beneficiaryTokenBalance,
                    JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                    PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS)
                ),
                JBConstants.MAX_REDEMPTION_RATE
            );

            // Calculate the fee from the redemption.
            uint256 _feeAmount = _ethReclaimAmount - _ethReclaimAmount * JBConstants.MAX_FEE / (_terminal.fee() + JBConstants.MAX_FEE);
            assertEq(_beneficiary.balance, _beneficiaryEthBalance + _ethReclaimAmount - _feeAmount);
            // Make sure the fee stays in the treasury.
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance - (_ethReclaimAmount - _feeAmount));
            
            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), 0);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance - (_ethReclaimAmount - _feeAmount));

            // Make sure the project owner got the expected number of tokens from the fee.
            assertEq(_tokenStore.balanceOf(_beneficiary, _FEE_PROJECT_ID), 0);
        }
    }

    function testFuzzETHAllowanceForTheFeeProject(uint232 _ethCurrencyOverflowAllowance, uint232 _ethCurrencyDistributionLimit, uint256 _ethPayAmount) public {
        // Make sure the amount of eth to pay is bounded. 
        _ethPayAmount = bound(_ethPayAmount, 0, 1000000 * 10**_ETH_DECIMALS);

        // Make sure the values don't overflow the registry.
        unchecked {
            vm.assume(_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit >= _ethCurrencyOverflowAllowance && _ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit >= _ethCurrencyDistributionLimit);
        }

        // Package up the constraints for the given terminal.
        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        {
            // Specify a distribution limit.
            JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](1);
            _distributionLimits[0] = JBCurrencyAmount({
                value: _ethCurrencyDistributionLimit,
                currency: uint24(uint160(JBTokens.ETH))
            });  

            // Specify an overflow allowance.
            JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](1);
            _overflowAllowances[0] = JBCurrencyAmount({
                value: _ethCurrencyOverflowAllowance,
                currency: uint24(uint160(JBTokens.ETH)) 
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
        _terminal.setAccountingContextFor({
            projectId: _projectId,
            token: JBTokens.ETH,
            standard: JBTokenStandards.NATIVE
        });

        // Make a payment to the project to give it a starting balance. Send the tokens to the _beneficiary.
        _terminal.pay{value: _ethPayAmount}({
            projectId: _projectId, 
            amount: _ethPayAmount, 
            token: JBTokens.ETH,
            beneficiary: _beneficiary, 
            minReturnedTokens: 0, 
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens.
        uint256 _beneficiaryTokenBalance = PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE;
        assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);

        // Make sure the terminal holds the full ETH balance.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount);

        // Revert if there's no allowance.
        if (_ethCurrencyOverflowAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        // Revert if there's no overflow, or if too much is being withdrawn.
        } else if (_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        }

        // Use the full discretionary allowance of overflow.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethCurrencyOverflowAllowance,
            currency: uint24(uint160(JBTokens.ETH)),
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary), 
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's balance;
        uint256 _beneficiaryEthBalance;

        // Check the collected balance if one is expected.
        if (_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance = PRBMath.mulDiv(_ethCurrencyOverflowAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryEthBalance);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv(_ethCurrencyOverflowAllowance - _beneficiaryEthBalance, _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
        } else {
            // Set the eth overflow allowance value to 0 if it wasnt used.
            _ethCurrencyOverflowAllowance = 0;
        }

        // Revert if the distribution limit is greater than the balance.
        if (_ethCurrencyDistributionLimit > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));

        // Revert if there's no distribution limit.
        } else if (_ethCurrencyDistributionLimit == 0) {
            vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
        }

        // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
        _terminal.distributePayoutsOf({
            projectId: _projectId,
            amount: _ethCurrencyDistributionLimit,
            currency: uint24(uint160(JBTokens.ETH)),
            token: JBTokens.ETH,
            minReturnedTokens: 0
        });

        uint256 _projectOwnerEthBalance;  

        // Check the collected distribution if one is expected.
        if (_ethCurrencyDistributionLimit <= _ethPayAmount && _ethCurrencyDistributionLimit != 0) {
            // Make sure the project owner received the distributed funds.
            _projectOwnerEthBalance = (_ethCurrencyDistributionLimit * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);
            assertEq(_projectOwner.balance, _projectOwnerEthBalance);
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance);

            // Make sure the project owner got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), PRBMath.mulDiv((_ethCurrencyOverflowAllowance - _beneficiaryEthBalance) + (_ethCurrencyDistributionLimit - _projectOwnerEthBalance), _data.weight, 10 ** _ETH_DECIMALS) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);
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
        if (_ethPayAmount > _ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit) {
            
            // Keep a reference to the total amount paid, including from fees.
            uint256 _totalPaid = _ethPayAmount + (_ethCurrencyOverflowAllowance - _beneficiaryEthBalance) + (_ethCurrencyDistributionLimit - _projectOwnerEthBalance);

            // Get the expected amount reclaimed.
            uint256 _ethReclaimAmount = PRBMath.mulDiv(
                PRBMath.mulDiv(_ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance, _beneficiaryTokenBalance, PRBMath.mulDiv(_totalPaid, _data.weight, 10 ** _ETH_DECIMALS)),
                _metadata.redemptionRate +
                PRBMath.mulDiv(
                    _beneficiaryTokenBalance,
                    JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                    PRBMath.mulDiv(_totalPaid, _data.weight, 10 ** _ETH_DECIMALS)
                ),
                JBConstants.MAX_REDEMPTION_RATE
            );
            // Calculate the fee from the redemption.
            uint256 _feeAmount = _ethReclaimAmount - _ethReclaimAmount * JBConstants.MAX_FEE / (_terminal.fee() + JBConstants.MAX_FEE);

            // Make sure the beneficiary has token from the fee just paid.
            assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), PRBMath.mulDiv(_feeAmount, _data.weight, 10 ** _ETH_DECIMALS ) * _metadata.reservedRate / JBConstants.MAX_RESERVED_RATE);

            // Make sure the beneficiary received the funds.
            assertEq(_beneficiary.balance, _beneficiaryEthBalance + _ethReclaimAmount - _feeAmount);

            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance - (_ethReclaimAmount - _feeAmount));
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance - (_ethReclaimAmount - _feeAmount));
        }
    }
    
    function testFuzzMultiCurrencyAllowance(uint232 _ethCurrencyOverflowAllowance, uint232 _ethCurrencyDistributionLimit, uint256 _ethPayAmount, uint232 _usdCurrencyOverflowAllowance, uint232 _usdCurrencyDistributionLimit, uint256 _usdcPayAmount) public {
        // Make sure the amount of eth to pay is bounded. 
        _ethPayAmount = bound(_ethPayAmount, 0, 1000000 * 10**_ETH_DECIMALS);
        _usdcPayAmount = bound(_usdcPayAmount, 0, 1000000 * 10**_usdcToken.decimals());

        // Make sure the values don't overflow the registry.
        unchecked {
            // vm.assume(_ethCurrencyOverflowAllowance + _cumulativeDistributionLimit  >= _ethCurrencyOverflowAllowance && _ethCurrencyOverflowAllowance + _cumulativeDistributionLimit >= _cumulativeDistributionLimit);
            // vm.assume(_usdCurrencyOverflowAllowance + (_usdCurrencyDistributionLimit + PRBMath.mulDiv(_ethCurrencyDistributionLimit, _USD_PRICE_PER_ETH, 10**_PRICE_FEED_DECIMALS))*2 >= _usdCurrencyOverflowAllowance && _usdCurrencyOverflowAllowance + _usdCurrencyDistributionLimit >= _usdCurrencyDistributionLimit);
            vm.assume(_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit >= _ethCurrencyOverflowAllowance && _ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit >= _ethCurrencyDistributionLimit);
            vm.assume(_usdCurrencyOverflowAllowance + _usdCurrencyDistributionLimit >= _usdCurrencyOverflowAllowance && _usdCurrencyOverflowAllowance + _usdCurrencyDistributionLimit >= _usdCurrencyDistributionLimit);
        }


        // Keep references to the projects.
        uint256 _projectId;
        {
            // Package up the constraints for the given terminal.
            JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);

            // Specify a distribution limit.
            JBCurrencyAmount[] memory _distributionLimits = new JBCurrencyAmount[](2);
            _distributionLimits[0] = JBCurrencyAmount({
                value: _ethCurrencyDistributionLimit,
                currency: uint24(uint160(JBTokens.ETH))
            });  
            _distributionLimits[1] = JBCurrencyAmount({
                value: _usdCurrencyDistributionLimit,
                currency: uint24(uint160(address(_usdcToken)))
            });  

            // Specify an overflow allowance.
            JBCurrencyAmount[] memory _overflowAllowances = new JBCurrencyAmount[](2);
            _overflowAllowances[0] = JBCurrencyAmount({
                value: _ethCurrencyOverflowAllowance,
                currency: uint24(uint160(JBTokens.ETH)) 
            });
            _overflowAllowances[1] = JBCurrencyAmount({
                value: _usdCurrencyOverflowAllowance,
                currency: uint24(uint160(address(_usdcToken)))
            });

            _fundAccessConstraints[0] =
                JBFundAccessConstraints({
                    terminal: _terminal,
                    token: JBTokens.ETH,
                    distributionLimits: _distributionLimits,
                    overflowAllowances: _overflowAllowances
                });

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
        _terminal.setAccountingContextFor({
            projectId: _FEE_PROJECT_ID,
            token: JBTokens.ETH,
            standard: JBTokenStandards.NATIVE
        });

        // Set the test project's terminal's ETH accounting context.
        _terminal.setAccountingContextFor({
            projectId: _projectId,
            token: JBTokens.ETH,
            standard: JBTokenStandards.NATIVE
        });

        // Set the fee collecting terminal's usdc accounting context.
        _terminal.setAccountingContextFor({
            projectId: _FEE_PROJECT_ID,
            token: address(_usdcToken),
            standard: JBTokenStandards.ERC20
        });

        // Set the test project's terminal's ETH accounting context.
        _terminal.setAccountingContextFor({
            projectId: _projectId,
            token: address(_usdcToken),
            standard: JBTokenStandards.ERC20
        });

        // Add a price feed to convert from ETH to USD currencies.
        {
            vm.startPrank(_multisig);
            MockPriceFeed _priceFeedEthUsd = new MockPriceFeed(_USD_PRICE_PER_ETH, _PRICE_FEED_DECIMALS);
            vm.label(address(_priceFeedEthUsd), "MockPrice Feed ETH-USDC");

            _prices.addFeedFor({
                projectId: 0,
                currency: uint24(uint160(address(_usdcToken))), 
                base: uint24(uint160(JBTokens.ETH)), 
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
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the beneficiary got the expected number of tokens from the ETH payment.
        uint256 _beneficiaryTokenBalance = _unreservedPortion(PRBMath.mulDiv(_ethPayAmount, _data.weight, 10 ** _ETH_DECIMALS));
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
            memo: "",
            metadata: new bytes(0)
        });

        // Make sure the usdc is accounted for.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, address(_usdcToken)), _usdcPayAmount);
        assertEq(_usdcToken.balanceOf(address(_terminal)), _usdcPayAmount);

        {
            // Convert the usd amount to an eth amount, byway of the current weight used for issuance.
            uint256 _usdWeightedPayAmountConvertedToEth = PRBMath.mulDiv(_usdcPayAmount, _data.weight, PRBMath.mulDiv(_USD_PRICE_PER_ETH, 10**_usdcToken.decimals(), 10**_PRICE_FEED_DECIMALS));

            // Make sure the beneficiary got the expected number of tokens from the USDC payment.
            _beneficiaryTokenBalance += _unreservedPortion(_usdWeightedPayAmountConvertedToEth);
            assertEq(_tokenStore.balanceOf(_beneficiary, _projectId), _beneficiaryTokenBalance);
        }
        // Make sure the terminal holds the full ETH balance.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount);

        // Make sure the terminal holds the full USDC balance.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, address(_usdcToken)), _usdcPayAmount);

        // Revert if there's no ETH allowance.
        if (_ethCurrencyOverflowAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        } else if (_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit + _toEth(_usdCurrencyDistributionLimit) > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        } 

        // Use the full discretionary ETH allowance of overflow.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _ethCurrencyOverflowAllowance,
            currency: uint24(uint160(JBTokens.ETH)),
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary), 
            memo: "MEMO"
        });

        // Keep a reference to the beneficiary's ETH balance;
        uint256 _beneficiaryEthBalance;

        // Check the collected balance if one is expected.
        if (_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit + _toEth(_usdCurrencyDistributionLimit) <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance = PRBMath.mulDiv(_ethCurrencyOverflowAllowance, JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethCurrencyOverflowAllowance);

            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), _ethCurrencyOverflowAllowance - _beneficiaryEthBalance);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), _unreservedPortion(PRBMath.mulDiv(_ethCurrencyOverflowAllowance - _beneficiaryEthBalance, _data.weight, 10 ** _ETH_DECIMALS)));
        } else {
            // Set the eth overflow allowance value to 0 if it wasnt used.
            _ethCurrencyOverflowAllowance = 0;
        }

        // Revert if there's no ETH allowance.
        if (_usdCurrencyOverflowAllowance == 0) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_CONTROLLER_ALLOWANCE()"));
        // revert if the usd overflow allowance resolved to eth is greater than 0, and there is sufficient overflow to pull from including what was already pulled from.
        } else if (_toEth(_usdCurrencyOverflowAllowance) > 0 && _toEth(_usdCurrencyOverflowAllowance + _usdCurrencyDistributionLimit) + _ethCurrencyDistributionLimit + _ethCurrencyOverflowAllowance > _ethPayAmount) {
            vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
        } 

        // Use the full discretionary ETH allowance of overflow.
        vm.prank(_projectOwner);
        _terminal.useAllowanceOf({
            projectId: _projectId,
            amount: _usdCurrencyOverflowAllowance,
            currency: uint24(uint160(address(_usdcToken))),
            token: JBTokens.ETH,
            minReturnedTokens: 0,
            beneficiary: payable(_beneficiary), 
            memo: "MEMO"
        });

        // Check the collected balance if one is expected.
        if (_ethCurrencyOverflowAllowance + _ethCurrencyDistributionLimit + _toEth(_usdCurrencyOverflowAllowance + _usdCurrencyDistributionLimit) <= _ethPayAmount) {
            // Make sure the beneficiary received the funds and that they are no longer in the terminal.
            _beneficiaryEthBalance += PRBMath.mulDiv(_toEth(_usdCurrencyOverflowAllowance), JBConstants.MAX_FEE, JBConstants.MAX_FEE + _terminal.fee());
            assertEq(_beneficiary.balance, _beneficiaryEthBalance);
            assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethCurrencyOverflowAllowance - _toEth(_usdCurrencyOverflowAllowance));

            // Make sure the fee was paid correctly.
            assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), _ethCurrencyOverflowAllowance + _toEth(_usdCurrencyOverflowAllowance) - _beneficiaryEthBalance);
            assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance);

            // Make sure the beneficiary got the expected number of tokens.
            assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), _unreservedPortion(PRBMath.mulDiv(_ethCurrencyOverflowAllowance + _toEth(_usdCurrencyOverflowAllowance) - _beneficiaryEthBalance, _data.weight, 10 ** _ETH_DECIMALS)));
        } else {
            // Set the eth overflow allowance value to 0 if it wasnt used.
            _usdCurrencyOverflowAllowance = 0;
        }
        
        // Distribution limits
        {
            // Revert if the distribution limit is greater than the balance.
            if (_ethCurrencyDistributionLimit > _ethPayAmount) {
                vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
            // Revert if there's no distribution limit.
            } else if (_ethCurrencyDistributionLimit == 0) {
                vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
            }

            // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
            _terminal.distributePayoutsOf({
                projectId: _projectId,
                amount: _ethCurrencyDistributionLimit,
                currency: uint24(uint160(JBTokens.ETH)),
                token: JBTokens.ETH,
                minReturnedTokens: 0
            });

            uint256 _projectOwnerEthBalance;  

            // Check the collected distribution if one is expected.
            if (_ethCurrencyDistributionLimit <= _ethPayAmount && _ethCurrencyDistributionLimit != 0) {
                // Make sure the project owner received the distributed funds.
                _projectOwnerEthBalance = (_ethCurrencyDistributionLimit * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);
                assertEq(_projectOwner.balance, _projectOwnerEthBalance);
                assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethCurrencyOverflowAllowance - _toEth(_usdCurrencyOverflowAllowance) - _ethCurrencyDistributionLimit);

                // Make sure the fee was paid correctly.
                assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), _ethCurrencyOverflowAllowance + _toEth(_usdCurrencyOverflowAllowance) - _beneficiaryEthBalance + _ethCurrencyDistributionLimit - _projectOwnerEthBalance);
                assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance);

                // Make sure the project owner got the expected number of tokens.
                // assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), _unreservedPortion(PRBMath.mulDiv(_ethCurrencyOverflowAllowance + _toEth(_usdCurrencyOverflowAllowance) - _beneficiaryEthBalance + _ethCurrencyDistributionLimit - _projectOwnerEthBalance, _data.weight, 10 ** _ETH_DECIMALS)));
            } 

            // Revert if the distribution limit is greater than the balance.
            if (_ethCurrencyDistributionLimit <= _ethPayAmount && _toEth(_usdCurrencyDistributionLimit) + _ethCurrencyDistributionLimit > _ethPayAmount) {
                vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
            } else if (_ethCurrencyDistributionLimit > _ethPayAmount && _toEth(_usdCurrencyDistributionLimit) > _ethPayAmount) {
                vm.expectRevert(abi.encodeWithSignature("INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()"));
            // Revert if there's no distribution limit.
            } else if (_usdCurrencyDistributionLimit == 0) {
                vm.expectRevert(abi.encodeWithSignature("DISTRIBUTION_AMOUNT_LIMIT_REACHED()"));
            }

            // Distribute the full amount of ETH. Since splits[] is empty, everything goes to project owner.
            _terminal.distributePayoutsOf({
                projectId: _projectId,
                amount: _usdCurrencyDistributionLimit,
                currency: uint24(uint160(address(_usdcToken))),
                token: JBTokens.ETH,
                minReturnedTokens: 0
            });

            // Check the collected distribution if one is expected.
            if (_toEth(_usdCurrencyDistributionLimit) + _ethCurrencyDistributionLimit <= _ethPayAmount && _usdCurrencyDistributionLimit > 0) {
                // Make sure the project owner received the distributed funds.
                _projectOwnerEthBalance += (_toEth(_usdCurrencyDistributionLimit) * JBConstants.MAX_FEE) / (_terminal.fee() + JBConstants.MAX_FEE);
                assertEq(_projectOwner.balance, _projectOwnerEthBalance);
                assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethPayAmount - _ethCurrencyOverflowAllowance - _toEth(_usdCurrencyOverflowAllowance) - _ethCurrencyDistributionLimit - _toEth(_usdCurrencyDistributionLimit));

                // Make sure the fee was paid correctly.
                assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, JBTokens.ETH), (_ethCurrencyOverflowAllowance + _toEth(_usdCurrencyOverflowAllowance) - _beneficiaryEthBalance) + (_ethCurrencyDistributionLimit +  _toEth(_usdCurrencyDistributionLimit) - _projectOwnerEthBalance));
                assertEq(address(_terminal).balance, _ethPayAmount - _beneficiaryEthBalance - _projectOwnerEthBalance);

                // Make sure the project owner got the expected number of tokens.
                // assertEq(_tokenStore.balanceOf(_projectOwner, _FEE_PROJECT_ID), _unreservedPortion(PRBMath.mulDiv(_ethCurrencyOverflowAllowance + _toEth(_usdCurrencyOverflowAllowance) - _beneficiaryEthBalance + _ethCurrencyDistributionLimit - _projectOwnerEthBalance, _data.weight, 10 ** _ETH_DECIMALS)));
            }
        }

        // Keep a reference to the eth overflow left. 
        uint256 _ethOverflow = _ethCurrencyDistributionLimit + _toEth(_usdCurrencyDistributionLimit) + _ethCurrencyOverflowAllowance + _toEth(_usdCurrencyOverflowAllowance) >= _ethPayAmount ? 0 : _ethPayAmount - _ethCurrencyDistributionLimit - _toEth(_usdCurrencyDistributionLimit) - _ethCurrencyOverflowAllowance - _toEth(_usdCurrencyOverflowAllowance);

        // Keep a reference to the eth balance left. 
        uint256 _ethBalance = _ethPayAmount - _ethCurrencyOverflowAllowance - _toEth(_usdCurrencyOverflowAllowance);
        if (_ethCurrencyDistributionLimit <= _ethPayAmount) {
            _ethBalance -= _ethCurrencyDistributionLimit;
            if (_toEth(_usdCurrencyDistributionLimit) + _ethCurrencyDistributionLimit < _ethPayAmount) _ethBalance -= _toEth(_usdCurrencyDistributionLimit);
        } else if (_toEth(_usdCurrencyDistributionLimit) <= _ethPayAmount) _ethBalance -= _toEth(_usdCurrencyDistributionLimit);

        // Make sure it's correct.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethBalance);

        // Make sure the usdc overflow is correct.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, address(_usdcToken)), _usdcPayAmount);

        // Make sure the total token supply is correct.
        assertEq(jbController().totalOutstandingTokensOf(_projectId), PRBMath.mulDiv(_beneficiaryTokenBalance, JBConstants.MAX_RESERVED_RATE, JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate)); 

        // Keep a reference to the amount of ETH being reclaimed.
        uint256 _ethReclaimAmount;

        vm.startPrank(_beneficiary);

        // If there's overflow.
        if (_toEth(PRBMath.mulDiv(_usdcPayAmount, 10**_ETH_DECIMALS, 10**_usdcToken.decimals())) + _ethOverflow > 0) {
            // Get the expected amount reclaimed.
            _ethReclaimAmount = PRBMath.mulDiv(
                PRBMath.mulDiv(_toEth(PRBMath.mulDiv(_usdcPayAmount, 10**_ETH_DECIMALS, 10**_usdcToken.decimals())) + _ethOverflow, _beneficiaryTokenBalance, PRBMath.mulDiv(_beneficiaryTokenBalance, JBConstants.MAX_RESERVED_RATE, JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate)),
                _metadata.redemptionRate +
                PRBMath.mulDiv(
                    _beneficiaryTokenBalance,
                    JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                    PRBMath.mulDiv(_beneficiaryTokenBalance, JBConstants.MAX_RESERVED_RATE, JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate)
                ),
                JBConstants.MAX_REDEMPTION_RATE
            );

            // If there is more to reclaim than there is ETH in the tank.
            if (_ethReclaimAmount > _ethOverflow) {
                
                // Keep a reference to the amount to redeem for ETH, a proportion of available overflow in ETH.
                uint256 _tokenCountToRedeemForEth = PRBMath.mulDiv(_beneficiaryTokenBalance, _ethOverflow, _ethOverflow + _toEth(PRBMath.mulDiv(_usdcPayAmount, 10**_ETH_DECIMALS, 10**_usdcToken.decimals())));
                uint256 _tokenSupply = PRBMath.mulDiv(_beneficiaryTokenBalance, JBConstants.MAX_RESERVED_RATE, JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate);
                // Redeem ETH from the overflow using only the _beneficiary's tokens needed to clear the ETH balance.
                _terminal.redeemTokensOf({
                    holder: _beneficiary,
                    projectId: _projectId,
                    tokenCount: _tokenCountToRedeemForEth, 
                    token: JBTokens.ETH,
                    minReturnedTokens: 0,
                    beneficiary: payable(_beneficiary),
                    metadata: new bytes(0)
                });
                    
                // Redeem USDC from the overflow using only the _beneficiary's tokens needed to clear the USDC balance.
                _terminal.redeemTokensOf({
                    holder: _beneficiary,
                    projectId: _projectId,
                    tokenCount: _beneficiaryTokenBalance - _tokenCountToRedeemForEth, 
                    token: address(_usdcToken),
                    minReturnedTokens: 0,
                    beneficiary: payable(_beneficiary),
                    metadata: new bytes(0)
                });

                _ethReclaimAmount = PRBMath.mulDiv(
                    PRBMath.mulDiv(_toEth(PRBMath.mulDiv(_usdcPayAmount, 10**_ETH_DECIMALS, 10**_usdcToken.decimals())) + _ethOverflow, _tokenCountToRedeemForEth, _tokenSupply),
                    _metadata.redemptionRate +
                    PRBMath.mulDiv(
                        _tokenCountToRedeemForEth,
                        JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                        _tokenSupply
                    ),
                    JBConstants.MAX_REDEMPTION_RATE
                );

                uint256 _usdcReclaimAmount = PRBMath.mulDiv(
                    PRBMath.mulDiv(_usdcPayAmount + _toUsd(PRBMath.mulDiv(_ethOverflow - _ethReclaimAmount, 10**_usdcToken.decimals(), 10**_ETH_DECIMALS)), _beneficiaryTokenBalance - _tokenCountToRedeemForEth, _tokenSupply - _tokenCountToRedeemForEth),
                    _metadata.redemptionRate +
                    PRBMath.mulDiv(
                        _beneficiaryTokenBalance - _tokenCountToRedeemForEth,
                        JBConstants.MAX_REDEMPTION_RATE - _metadata.redemptionRate,
                        _tokenSupply - _tokenCountToRedeemForEth
                    ),
                    JBConstants.MAX_REDEMPTION_RATE
                );

                assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, address(_usdcToken)), _usdcPayAmount - _usdcReclaimAmount);

                uint256 _usdcFeeAmount = _usdcReclaimAmount - _usdcReclaimAmount * JBConstants.MAX_FEE / (_terminal.fee() + JBConstants.MAX_FEE);
                // assertEq(_usdcToken.balanceOf(_beneficiary), _usdcReclaimAmount - _usdcFeeAmount);

                // Make sure the fee was paid correctly.
                // assertEq(jbTerminalStore().balanceOf(_terminal, _FEE_PROJECT_ID, address(_usdcToken)), _usdcFeeAmount);
                // assertEq(_usdcToken.balanceOf(address(_terminal)), _usdcPayAmount - _usdcReclaimAmount + _usdcFeeAmount);
            } else {
                // Redeem ETH from the overflow using all of the _beneficiary's tokens.
                _terminal.redeemTokensOf({
                    holder: _beneficiary,
                    projectId: _projectId,
                    tokenCount: _beneficiaryTokenBalance, 
                    token: JBTokens.ETH,
                    minReturnedTokens: 0,
                    beneficiary: payable(_beneficiary),
                    metadata: new bytes(0)
                });
            }
        // burn the tokens.
        } else {
            _terminal.redeemTokensOf({
                holder: _beneficiary,
                projectId: _projectId,
                tokenCount: _beneficiaryTokenBalance, 
                token: address(_usdcToken),
                minReturnedTokens: 0,
                beneficiary: payable(_beneficiary),
                metadata: new bytes(0)
            });
        }
        vm.stopPrank();

        // Make sure the balance is adjusted by the reclaim amount.
        assertEq(jbTerminalStore().balanceOf(_terminal, _projectId, JBTokens.ETH), _ethBalance - _ethReclaimAmount);
    }

    function _toEth(uint256 _usdVal) pure internal returns (uint256) {
        return PRBMath.mulDiv(_usdVal, 10**_PRICE_FEED_DECIMALS, _USD_PRICE_PER_ETH);
    }

    function _toUsd(uint256 _ethVal) pure internal returns (uint256) {
        return PRBMath.mulDiv(_ethVal, _USD_PRICE_PER_ETH, 10**_PRICE_FEED_DECIMALS);
    }

    function _unreservedPortion(uint256 _fullPortion) view internal returns (uint256) {
        return PRBMath.mulDiv(_fullPortion, JBConstants.MAX_RESERVED_RATE - _metadata.reservedRate, JBConstants.MAX_RESERVED_RATE);
    }
}