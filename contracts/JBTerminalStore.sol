// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PRBMath} from "@paulrberg/contracts/math/PRBMath.sol";
import {IJBController} from "./interfaces/IJBController.sol";
import {IJBDirectory} from "./interfaces/IJBDirectory.sol";
import {IJBRulesetDataSource} from "./interfaces/IJBRulesetDataSource.sol";
import {IJBRulesets} from "./interfaces/IJBRulesets.sol";
import {IJBPaymentTerminal} from "./interfaces/IJBPaymentTerminal.sol";
import {IJBPrices} from "./interfaces/IJBPrices.sol";
import {IJBPrices} from "./interfaces/IJBPrices.sol";
import {IJBPaymentTerminal} from "./interfaces/IJBPaymentTerminal.sol";
import {IJBTerminalStore} from "./interfaces/IJBTerminalStore.sol";
import {JBConstants} from "./libraries/JBConstants.sol";
import {JBFixedPointNumber} from "./libraries/JBFixedPointNumber.sol";
import {JBCurrencyAmount} from "./structs/JBCurrencyAmount.sol";
import {JBRulesetMetadataResolver} from "./libraries/JBRulesetMetadataResolver.sol";
import {JBRuleset} from "./structs/JBRuleset.sol";
import {JBPayDelegateAllocation} from "./structs/JBPayDelegateAllocation.sol";
import {JBPayParamsData} from "./structs/JBPayParamsData.sol";
import {JBRedeemParamsData} from "./structs/JBRedeemParamsData.sol";
import {JBRedeemDelegateAllocation} from "./structs/JBRedeemDelegateAllocation.sol";
import {JBAccountingContext} from "./structs/JBAccountingContext.sol";
import {JBTokenAmount} from "./structs/JBTokenAmount.sol";

/// @notice Manages all bookkeeping for inflows and outflows of funds from any ISingleTokenPaymentTerminal.
/// @dev This Store expects a project's controller to be an IJBController.
contract JBTerminalStore is ReentrancyGuard, IJBTerminalStore {
    // A library that parses the packed ruleset metadata into a friendlier format.
    using JBRulesetMetadataResolver for JBRuleset;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error INVALID_AMOUNT_TO_SEND_DELEGATE();
    error CURRENCY_MISMATCH();
    error DISTRIBUTION_AMOUNT_LIMIT_REACHED();
    error RULESET_PAYMENT_PAUSED();
    error RULESET_DISTRIBUTION_PAUSED();
    error RULESET_REDEEM_PAUSED();
    error INADEQUATE_CONTROLLER_ALLOWANCE();
    error INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE();
    error INSUFFICIENT_TOKENS();
    error INVALID_RULESET();
    error PAYMENT_TERMINAL_MIGRATION_NOT_ALLOWED();

    //*********************************************************************//
    // -------------------------- private constants ---------------------- //
    //*********************************************************************//

    /// @notice Ensures a maximum number of decimal points of persisted fidelity on mulDiv operations of fixed point numbers.
    uint256 private constant _MAX_FIXED_POINT_FIDELITY = 18;

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable override DIRECTORY;

    /// @notice The contract storing all ruleset configurations.
    IJBRulesets public immutable override RULESET_STORE;

    /// @notice The contract that exposes price feeds.
    IJBPrices public immutable override PRICES;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The amount of tokens that each project has for each terminal, in terms of the terminal's token.
    /// @dev The balance is represented as a fixed point number with the same amount of decimals as its relative terminal.
    /// @custom:param _terminal The terminal to which the balance applies.
    /// @custom:param _projectId The ID of the project to get the balance of.
    /// @custom:param _token The token to which the balance applies.
    /// @custom:param _token The token to which the balance applies.
    mapping(IJBPaymentTerminal => mapping(uint256 => mapping(address => uint256))) public override
        balanceOf;

    /// @notice The currency-denominated amounts of funds that a project has distributed from its limit during the current ruleset for each terminal.
    /// @dev Increases as projects use their preconfigured payout limits.
    /// @dev The used payout limit is represented as a fixed point number with the same amount of decimals as its relative terminal.
    /// @custom:param _terminal The terminal to which the used payout limit applies.
    /// @custom:param _projectId The ID of the project to get the used payout limit of.
    /// @custom:param _token The token to which the used payout limit applies.
    /// @custom:param _rulesetNumber The number of the ruleset during which the payout limit was used.
    /// @custom:param _currency The currency for which the payout limit applies.
    mapping(
        IJBPaymentTerminal
            => mapping(
                uint256 => mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
            )
    ) public override usedPayoutLimitOf;

    /// @notice The currency-denominated amounts of funds that a project has used from its allowance during the current ruleset configuration for each terminal, in terms of the surplus allowance's currency.
    /// @dev Increases as projects use their allowance.
    /// @dev The used allowance is represented as a fixed point number with the same amount of decimals as its relative terminal.
    /// @custom:param _terminal The terminal to which the used surplus allowance applies.
    /// @custom:param _projectId The ID of the project to get the used surplus allowance of.
    /// @custom:param _token The token to which the used surplus allowance applies.
    /// @custom:param _rulesetId The rulesetId of the during which the allowance was used.
    /// @custom:param _currency The currency for which the surplus allowance applies.
    mapping(
        IJBPaymentTerminal
            => mapping(
                uint256 => mapping(address => mapping(uint256 => mapping(uint256 => uint256)))
            )
    ) public override usedSurplusAllowanceOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Gets the current surplused amount in a terminal for a specified project.
    /// @dev The current surplus is represented as a fixed point number with the same amount of decimals as the specified terminal.
    /// @param _terminal The terminal for which the surplus is being calculated.
    /// @param _projectId The ID of the project to get surplus for.
    /// @param _accountingContexts The accounting contexts of tokens whose balances should contribute to the surplus being reclaimed from.
    /// @param _currency The currency the result should be in terms of.
    /// @param _decimals The number of decimals to expect in the resulting fixed point number.
    /// @return The current amount of surplus that project has in the specified terminal.
    function currentSurplusOf(
        IJBPaymentTerminal _terminal,
        uint256 _projectId,
        JBAccountingContext[] calldata _accountingContexts,
        uint256 _decimals,
        uint256 _currency
    ) external view override returns (uint256) {
        // Return the surplus during the project's current ruleset.
        return _surplusFrom(
            _terminal,
            _projectId,
            _accountingContexts,
            RULESET_STORE.currentOf(_projectId),
            _decimals,
            _currency
        );
    }

    /// @notice Gets the current surplused amount for a specified project across all terminals.
    /// @param _projectId The ID of the project to get total surplus for.
    /// @param _decimals The number of decimals that the fixed point surplus should include.
    /// @param _currency The currency that the total surplus should be in terms of.
    /// @return The current total amount of surplus that project has across all terminals.
    function currentTotalSurplusOf(uint256 _projectId, uint256 _decimals, uint256 _currency)
        external
        view
        override
        returns (uint256)
    {
        return _currentTotalSurplusOf(_projectId, _decimals, _currency);
    }

    /// @notice The current amount of surplused tokens from a terminal that can be reclaimed by the specified number of tokens, using the total token supply and surplus in the ecosystem.
    /// @dev The current reclaimable surplus is returned in terms of the specified terminal's currency.
    /// @dev The reclaimable surplus is represented as a fixed point number with the same amount of decimals as the specified terminal.
    /// @param _terminal The terminal from which the reclaimable amount would come.
    /// @param _projectId The ID of the project to get the reclaimable surplus amount for.
    /// @param _accountingContexts The accounting contexts of tokens whose balances should contribute to the surplus being reclaimed from.
    /// @param _decimals The number of decimals to include in the resulting fixed point number.
    /// @param _currency The currency the resulting number will be in terms of.
    /// @param _tokenCount The number of tokens to make the calculation with, as a fixed point number with 18 decimals.
    /// @param _useTotalSurplus A flag indicating whether the surplus used in the calculation should be summed from all of the project's terminals. If false, surplus should be limited to the amount in the specified `_terminal`.
    /// @return The amount of surplused tokens that can be reclaimed, as a fixed point number with the same number of decimals as the provided `_terminal`.
    function currentReclaimableSurplusOf(
        IJBPaymentTerminal _terminal,
        uint256 _projectId,
        JBAccountingContext[] calldata _accountingContexts,
        uint256 _decimals,
        uint256 _currency,
        uint256 _tokenCount,
        bool _useTotalSurplus
    ) external view override returns (uint256) {
        // Get a reference to the project's current ruleset.
        JBRuleset memory _ruleset = RULESET_STORE.currentOf(_projectId);

        // Get the amount of current surplus.
        // Use the project's total surplus across all of its terminals if the flag species specifies so. Otherwise, use the surplus local to the specified terminal.
        uint256 _currentSurplus = _useTotalSurplus
            ? _currentTotalSurplusOf(_projectId, _decimals, _currency)
            : _surplusFrom(_terminal, _projectId, _accountingContexts, _ruleset, _decimals, _currency);

        // If there's no surplus, there's no reclaimable surplus.
        if (_currentSurplus == 0) return 0;

        // Get the number of outstanding tokens the project has.
        uint256 _totalSupply =
            IJBController(DIRECTORY.controllerOf(_projectId)).totalOutstandingTokensOf(_projectId);

        // Can't redeem more tokens that is in the supply.
        if (_tokenCount > _totalSupply) return 0;

        // Return the reclaimable surplus amount.
        return _reclaimableSurplusDuring(_ruleset, _tokenCount, _totalSupply, _currentSurplus);
    }

    /// @notice The current amount of surplused tokens from a terminal that can be reclaimed by the specified number of tokens, using the specified total token supply and surplus amounts.
    /// @param _projectId The ID of the project to get the reclaimable surplus amount for.
    /// @param _tokenCount The number of tokens to make the calculation with, as a fixed point number with 18 decimals.
    /// @param _totalSupply The total number of tokens to make the calculation with, as a fixed point number with 18 decimals.
    /// @param _surplus The amount of surplus to make the calculation with, as a fixed point number.
    /// @return The amount of surplused tokens that can be reclaimed, as a fixed point number with the same number of decimals as the provided `_surplus`.
    function currentReclaimableSurplusOf(
        uint256 _projectId,
        uint256 _tokenCount,
        uint256 _totalSupply,
        uint256 _surplus
    ) external view override returns (uint256) {
        // If there's no surplus, there's no reclaimable surplus.
        if (_surplus == 0) return 0;

        // Can't redeem more tokens that is in the supply.
        if (_tokenCount > _totalSupply) return 0;

        // Get a reference to the project's current ruleset.
        JBRuleset memory _ruleset = RULESET_STORE.currentOf(_projectId);

        // Return the reclaimable surplus amount.
        return _reclaimableSurplusDuring(_ruleset, _tokenCount, _totalSupply, _surplus);
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param _directory A contract storing directories of terminals and controllers for each project.
    /// @param _rulesets A contract storing all ruleset configurations.
    /// @param _prices A contract that exposes price feeds.
    constructor(IJBDirectory _directory, IJBRulesets _rulesets, IJBPrices _prices) {
        DIRECTORY = _directory;
        RULESET_STORE = _rulesets;
        PRICES = _prices;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Records newly contributed tokens to a project.
    /// @dev Mints the project's tokens according to values provided by a configured data source. If no data source is configured, mints tokens proportional to the amount of the contribution.
    /// @dev The msg.sender must be an IJBPaymentTerminal. The amount specified in the params is in terms of the msg.sender's tokens.
    /// @param _payer The original address that sent the payment to the terminal.
    /// @param _amount The amount of tokens being paid. Includes the token being paid, the value, the number of decimals included, and the currency of the amount.
    /// @param _projectId The ID of the project being paid.
    /// @param _beneficiary The specified address that should be the beneficiary of anything that results from the payment.
    /// @param _metadata Bytes to send along to the data source, if one is provided.
    /// @return ruleset The project's ruleset during which payment was made.
    /// @return tokenCount The number of project tokens that were minted, as a fixed point number with 18 decimals.
    /// @return delegateAllocations The amount to send to delegates instead of adding to the local balance.
    function recordPaymentFrom(
        address _payer,
        JBTokenAmount calldata _amount,
        uint256 _projectId,
        address _beneficiary,
        bytes calldata _metadata
    )
        external
        override
        nonReentrant
        returns (
            JBRuleset memory ruleset,
            uint256 tokenCount,
            JBPayDelegateAllocation[] memory delegateAllocations
        )
    {
        // Get a reference to the current ruleset for the project.
        ruleset = RULESET_STORE.currentOf(_projectId);

        // The project must have a ruleset configured.
        if (ruleset.cycleNumber == 0) revert INVALID_RULESET();

        // Must not be paused.
        if (ruleset.payPaused()) revert RULESET_PAYMENT_PAUSED();

        // The weight according to which new token supply is to be minted, as a fixed point number with 18 decimals.
        uint256 _weight;

        // If the ruleset has configured a data source, use it to derive a weight and memo.
        if (ruleset.useDataSourceForPay() && ruleset.dataSource() != address(0)) {
            // Create the params that'll be sent to the data source.
            JBPayParamsData memory _data = JBPayParamsData(
                IJBPaymentTerminal(msg.sender),
                _payer,
                _amount,
                _projectId,
                ruleset.rulesetId,
                _beneficiary,
                ruleset.weight,
                ruleset.reservedRate(),
                _metadata
            );
            (_weight, delegateAllocations) =
                IJBRulesetDataSource(ruleset.dataSource()).payParams(_data);
        }
        // Otherwise use the ruleset's weight
        else {
            _weight = ruleset.weight;
        }

        // Keep a reference to the amount that should be added to the project's balance.
        uint256 _balanceDiff = _amount.value;

        // Scoped section preventing stack too deep.
        {
            // Keep a reference to the number of delegate allocations.
            uint256 _numberOfDelegateAllocations = delegateAllocations.length;

            // Validate all delegated amounts. This needs to be done before returning the delegate allocations to ensure valid delegated amounts.
            if (_numberOfDelegateAllocations != 0) {
                for (uint256 _i; _i < _numberOfDelegateAllocations;) {
                    // Get a reference to the amount to be delegated.
                    uint256 _delegatedAmount = delegateAllocations[_i].amount;

                    // Validate if non-zero.
                    if (_delegatedAmount != 0) {
                        // Can't delegate more than was paid.
                        if (_delegatedAmount > _balanceDiff) {
                            revert INVALID_AMOUNT_TO_SEND_DELEGATE();
                        }

                        // Decrement the total amount being added to the balance.
                        _balanceDiff = _balanceDiff - _delegatedAmount;
                    }

                    unchecked {
                        ++_i;
                    }
                }
            }
        }

        // If there's no amount being recorded, there's nothing left to do.
        if (_amount.value == 0) return (ruleset, 0, delegateAllocations);

        // Add the correct balance difference to the token balance of the project.
        if (_balanceDiff != 0) {
            balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_amount.token] =
                balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_amount.token] + _balanceDiff;
        }

        // If there's no weight, token count must be 0 so there's nothing left to do.
        if (_weight == 0) return (ruleset, 0, delegateAllocations);

        // If the terminal should base its weight on a different currency from the terminal's currency, determine the factor.
        // The weight is always a fixed point mumber with 18 decimals. To ensure this, the ratio should use the same number of decimals as the `_amount`.
        uint256 _weightRatio = _amount.currency == ruleset.baseCurrency()
            ? 10 ** _amount.decimals
            : PRICES.pricePerUnitOf(
                _projectId, _amount.currency, ruleset.baseCurrency(), _amount.decimals
            );

        // Find the number of tokens to mint, as a fixed point number with as many decimals as `weight` has.
        tokenCount = PRBMath.mulDiv(_amount.value, _weight, _weightRatio);
    }

    /// @notice Records newly redeemed tokens of a project.
    /// @dev Redeems the project's tokens according to values provided by a configured data source. If no data source is configured, redeems tokens along a redemption bonding curve that is a function of the number of tokens being burned.
    /// @dev The msg.sender must be an IJBPaymentTerminal. The amount specified in the params is in terms of the msg.senders tokens.
    /// @param _holder The account that is having its tokens redeemed.
    /// @param _projectId The ID of the project to which the tokens being redeemed belong.
    /// @param _accountingContext The accounting context of the token being reclaimed from the redemption.
    /// @param _balanceTokenContexts The token contexts whose balances should contribute to the surplus being reclaimed from.
    /// @param _tokenCount The number of project tokens to redeem, as a fixed point number with 18 decimals.
    /// @param _metadata Bytes to send along to the data source, if one is provided.
    /// @return ruleset The ruleset during which the redemption was made.
    /// @return reclaimAmount The amount of terminal tokens reclaimed, as a fixed point number with 18 decimals.
    /// @return delegateAllocations The amount to send to delegates instead of sending to the beneficiary.
    function recordRedemptionFor(
        address _holder,
        uint256 _projectId,
        JBAccountingContext calldata _accountingContext,
        JBAccountingContext[] calldata _balanceTokenContexts,
        uint256 _tokenCount,
        bytes memory _metadata
    )
        external
        override
        nonReentrant
        returns (
            JBRuleset memory ruleset,
            uint256 reclaimAmount,
            JBRedeemDelegateAllocation[] memory delegateAllocations
        )
    {
        // Get a reference to the project's current ruleset.
        ruleset = RULESET_STORE.currentOf(_projectId);

        // Get the amount of current surplus.
        // Use the local surplus if the ruleset specifies that it should be used. Otherwise, use the project's total surplus across all of its terminals.
        uint256 _currentSurplus = ruleset.useTotalSurplusForRedemptions()
            ? _currentTotalSurplusOf(
                _projectId, _accountingContext.decimals, _accountingContext.currency
            )
            : _surplusFrom(
                IJBPaymentTerminal(msg.sender),
                _projectId,
                _balanceTokenContexts,
                ruleset,
                _accountingContext.decimals,
                _accountingContext.currency
            );

        // Get the number of outstanding tokens the project has.
        uint256 _totalSupply =
            IJBController(DIRECTORY.controllerOf(_projectId)).totalOutstandingTokensOf(_projectId);

        // Can't redeem more tokens that is in the supply.
        if (_tokenCount > _totalSupply) revert INSUFFICIENT_TOKENS();

        if (_currentSurplus != 0) {
            // Calculate reclaim amount using the current surplus amount.
            reclaimAmount =
                _reclaimableSurplusDuring(ruleset, _tokenCount, _totalSupply, _currentSurplus);
        }

        // Create the struct that describes the amount being reclaimed.
        JBTokenAmount memory _reclaimedTokenAmount = JBTokenAmount(
            _accountingContext.token,
            reclaimAmount,
            _accountingContext.decimals,
            _accountingContext.currency
        );

        // If the ruleset has configured a data source, use it to derive a claim amount and memo.
        if (ruleset.useDataSourceForRedeem() && ruleset.dataSource() != address(0)) {
            // Yet another scoped section prevents stack too deep. `_state`  only used within scope.
            {
                // Create the params that'll be sent to the data source.
                JBRedeemParamsData memory _data = JBRedeemParamsData(
                    IJBPaymentTerminal(msg.sender),
                    _holder,
                    _projectId,
                    ruleset.rulesetId,
                    _tokenCount,
                    _totalSupply,
                    _currentSurplus,
                    _reclaimedTokenAmount,
                    ruleset.useTotalSurplusForRedemptions(),
                    ruleset.redemptionRate(),
                    _metadata
                );
                (reclaimAmount, delegateAllocations) =
                    IJBRulesetDataSource(ruleset.dataSource()).redeemParams(_data);
            }
        }

        // Keep a reference to the amount that should be subtracted from the project's balance.
        uint256 _balanceDiff = reclaimAmount;

        if (delegateAllocations.length != 0) {
            // Validate all delegated amounts.
            for (uint256 _i; _i < delegateAllocations.length;) {
                // Get a reference to the amount to be delegated.
                uint256 _delegatedAmount = delegateAllocations[_i].amount;

                // Validate if non-zero.
                if (_delegatedAmount != 0) {
                    // Increment the total amount being subtracted from the balance.
                    _balanceDiff = _balanceDiff + _delegatedAmount;
                }

                unchecked {
                    ++_i;
                }
            }
        }

        // The amount being reclaimed must be within the project's balance.
        if (
            _balanceDiff
                > balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext.token]
        ) revert INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE();

        // Remove the reclaimed funds from the project's balance.
        if (_balanceDiff != 0) {
            unchecked {
                balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext.token] =
                balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext.token]
                    - _balanceDiff;
            }
        }
    }

    /// @notice Records newly distributed funds for a project.
    /// @dev The msg.sender must be an IJBPaymentTerminal.
    /// @param _projectId The ID of the project that is having funds distributed.
    /// @param _accountingContext The context of the token being distributed.
    /// @param _amount The amount to use from the payout limit, as a fixed point number.
    /// @param _currency The currency of the `_amount`. This must match the project's current ruleset's currency.
    /// @return ruleset The ruleset during which the distribution was made.
    /// @return distributedAmount The amount of terminal tokens distributed, as a fixed point number with the same amount of decimals as its relative terminal.
    function recordDistributionFor(
        uint256 _projectId,
        JBAccountingContext calldata _accountingContext,
        uint256 _amount,
        uint256 _currency
    )
        external
        override
        nonReentrant
        returns (JBRuleset memory ruleset, uint256 distributedAmount)
    {
        // Get a reference to the project's current ruleset.
        ruleset = RULESET_STORE.currentOf(_projectId);

        // The new total amount that has been distributed during this ruleset.
        uint256 _newUsedPayoutLimitOf = usedPayoutLimitOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext
            .token][ruleset.cycleNumber][_currency] + _amount;

        // Amount must be within what is still distributable.
        uint256 _payoutLimit = IJBController(DIRECTORY.controllerOf(_projectId)).fundAccessLimits()
            .payoutLimitOf(
            _projectId,
            ruleset.rulesetId,
            IJBPaymentTerminal(msg.sender),
            _accountingContext.token,
            _currency
        );

        // Make sure the new used amount is within the payout limit.
        if (_newUsedPayoutLimitOf > _payoutLimit || _payoutLimit == 0) {
            revert DISTRIBUTION_AMOUNT_LIMIT_REACHED();
        }

        // Get a reference to the terminal's decimals.
        JBAccountingContext memory _balanceContext = IJBPaymentTerminal(msg.sender)
            .accountingContextForTokenOf(_projectId, _accountingContext.token);

        // Convert the amount to the balance's currency.
        distributedAmount = (_currency == _balanceContext.currency)
            ? _amount
            : PRBMath.mulDiv(
                _amount,
                10 ** _MAX_FIXED_POINT_FIDELITY, // Use _MAX_FIXED_POINT_FIDELITY to keep as much of the `_amount`'s fidelity as possible when converting.
                PRICES.pricePerUnitOf(
                    _projectId, _currency, _balanceContext.currency, _MAX_FIXED_POINT_FIDELITY
                )
            );

        // The amount being distributed must be available.
        if (
            distributedAmount
                > balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext.token]
        ) revert INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE();

        // Store the new amount.
        usedPayoutLimitOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext.token][ruleset
            .cycleNumber][_currency] = _newUsedPayoutLimitOf;

        // Removed the distributed funds from the project's token balance.
        unchecked {
            balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext.token] =
            balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext.token]
                - distributedAmount;
        }
    }

    /// @notice Records newly used allowance funds of a project.
    /// @dev The msg.sender must be an IJBPaymentTerminal.
    /// @param _projectId The ID of the project to use the allowance of.
    /// @param _accountingContext The accounting context of the token whose balances should contribute to the surplus being reclaimed from.
    /// @param _amount The amount to use from the allowance, as a fixed point number.
    /// @param _currency The currency of the `_amount`. Must match the currency of the surplus allowance.
    /// @return ruleset The ruleset during which the surplus allowance is being used.
    /// @return usedAmount The amount of terminal tokens used, as a fixed point number with the same amount of decimals as its relative terminal.
    function recordUsedAllowanceOf(
        uint256 _projectId,
        JBAccountingContext calldata _accountingContext,
        uint256 _amount,
        uint256 _currency
    ) external override nonReentrant returns (JBRuleset memory ruleset, uint256 usedAmount) {
        // Get a reference to the project's current ruleset.
        ruleset = RULESET_STORE.currentOf(_projectId);

        // Get a reference to the new used surplus allowance for this ruleset rulesetId.
        uint256 _newUsedSurplusAllowanceOf = usedSurplusAllowanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext
            .token][ruleset.rulesetId][_currency] + _amount;

        // There must be sufficient allowance available.
        uint256 _surplusAllowance = IJBController(DIRECTORY.controllerOf(_projectId))
            .fundAccessLimits().surplusAllowanceOf(
            _projectId,
            ruleset.rulesetId,
            IJBPaymentTerminal(msg.sender),
            _accountingContext.token,
            _currency
        );

        // Make sure the new used amount is within the allowance.
        if (_newUsedSurplusAllowanceOf > _surplusAllowance || _surplusAllowance == 0) {
            revert INADEQUATE_CONTROLLER_ALLOWANCE();
        }

        // Convert the amount to this store's terminal's token.
        usedAmount = _currency == _accountingContext.currency
            ? _amount
            : PRBMath.mulDiv(
                _amount,
                10 ** _MAX_FIXED_POINT_FIDELITY, // Use _MAX_FIXED_POINT_FIDELITY to keep as much of the `_amount`'s fidelity as possible when converting.
                PRICES.pricePerUnitOf(
                    _projectId, _currency, _accountingContext.currency, _MAX_FIXED_POINT_FIDELITY
                )
            );

        // Set the token being used as the only one to look for surplus within.
        JBAccountingContext[] memory _accountingContexts = new JBAccountingContext[](1);
        _accountingContexts[0] = _accountingContext;

        // The amount being distributed must be available in the surplus.
        if (
            usedAmount
                > _surplusFrom(
                    IJBPaymentTerminal(msg.sender),
                    _projectId,
                    _accountingContexts,
                    ruleset,
                    _accountingContext.decimals,
                    _accountingContext.currency
                )
        ) revert INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE();

        // Store the incremented value.
        usedSurplusAllowanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext.token][ruleset
            .rulesetId][_currency] = _newUsedSurplusAllowanceOf;

        // Update the project's balance.
        balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_accountingContext.token] = balanceOf[IJBPaymentTerminal(
            msg.sender
        )][_projectId][_accountingContext.token] - usedAmount;
    }

    /// @notice Records newly added funds for the project.
    /// @dev The msg.sender must be an IJBPaymentTerminal.
    /// @param _projectId The ID of the project to which the funds being added belong.
    /// @param _token The token being added to the balance.
    /// @param _amount The amount of terminal tokens added, as a fixed point number with the same amount of decimals as its relative terminal.
    function recordAddedBalanceFor(uint256 _projectId, address _token, uint256 _amount)
        external
        override
    {
        // Increment the balance.
        balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_token] =
            balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_token] + _amount;
    }

    /// @notice Records the migration of funds from this store.
    /// @dev The msg.sender must be an IJBPaymentTerminal. The amount returned is in terms of the msg.senders tokens.
    /// @param _projectId The ID of the project being migrated.
    /// @param _token The token being migrated.
    /// @return balance The project's migrated balance, as a fixed point number with the same amount of decimals as its relative terminal.
    function recordMigration(uint256 _projectId, address _token)
        external
        override
        nonReentrant
        returns (uint256 balance)
    {
        // Get a reference to the project's current ruleset.
        JBRuleset memory _ruleset = RULESET_STORE.currentOf(_projectId);

        // Migration must be allowed.
        if (!_ruleset.terminalMigrationAllowed()) {
            revert PAYMENT_TERMINAL_MIGRATION_NOT_ALLOWED();
        }

        // Return the current balance.
        balance = balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_token];

        // Set the balance to 0.
        balanceOf[IJBPaymentTerminal(msg.sender)][_projectId][_token] = 0;
    }

    //*********************************************************************//
    // --------------------- private helper functions -------------------- //
    //*********************************************************************//

    /// @notice The amount of surplused tokens from a terminal that can be reclaimed by the specified number of tokens when measured from the specified.
    /// @dev If the project has an active ruleset reconfiguration approval hook, the project's approval hook redemption rate is used.
    /// @param _ruleset The ruleset during which reclaimable surplus is being calculated.
    /// @param _tokenCount The number of tokens to make the calculation with, as a fixed point number with 18 decimals.
    /// @param _totalSupply The total supply of tokens to make the calculation with, as a fixed point number with 18 decimals.
    /// @param _surplus The amount of surplus to make the calculation with.
    /// @return The amount of surplused tokens that can be reclaimed.
    function _reclaimableSurplusDuring(
        JBRuleset memory _ruleset,
        uint256 _tokenCount,
        uint256 _totalSupply,
        uint256 _surplus
    ) private pure returns (uint256) {
        // If the amount being redeemed is the total supply, return the rest of the surplus.
        if (_tokenCount == _totalSupply) return _surplus;

        // If the redemption rate is 0, nothing is claimable.
        if (_ruleset.redemptionRate() == 0) return 0;

        // Get a reference to the linear proportion.
        uint256 _base = PRBMath.mulDiv(_surplus, _tokenCount, _totalSupply);

        // These conditions are all part of the same curve. Edge conditions are separated because fewer operation are necessary.
        if (_ruleset.redemptionRate() == JBConstants.MAX_REDEMPTION_RATE) {
            return _base;
        }

        return PRBMath.mulDiv(
            _base,
            _ruleset.redemptionRate()
                + PRBMath.mulDiv(
                    _tokenCount,
                    JBConstants.MAX_REDEMPTION_RATE - _ruleset.redemptionRate(),
                    _totalSupply
                ),
            JBConstants.MAX_REDEMPTION_RATE
        );
    }

    /// @notice Gets the amount that is surplusing when measured from the specified ruleset.
    /// @dev This amount changes as the value of the balance changes in relation to the currency being used to measure the payout limit.
    /// @param _terminal The terminal for which the surplus is being calculated.
    /// @param _projectId The ID of the project to get surplus for.
    /// @param _accountingContexts The accounting contexts of tokens whose balances should contribute to the surplus being measured.
    /// @param _ruleset The ID of the ruleset to base the surplus on.
    /// @param _targetDecimals The number of decimals to include in the resulting fixed point number.
    /// @param _targetCurrency The currency that the reported surplus is expected to be in terms of.
    /// @return surplus The surplus of funds, as a fixed point number with 18 decimals.
    function _surplusFrom(
        IJBPaymentTerminal _terminal,
        uint256 _projectId,
        JBAccountingContext[] memory _accountingContexts,
        JBRuleset memory _ruleset,
        uint256 _targetDecimals,
        uint256 _targetCurrency
    ) private view returns (uint256 surplus) {
        // Keep a reference to the number of tokens being iterated on.
        uint256 _numberOfTokenAccountingContexts = _accountingContexts.length;

        // Add payout limits from each token.
        for (uint256 _i; _i < _numberOfTokenAccountingContexts;) {
            uint256 _tokenSurplus = _tokenSurplusFrom(
                _terminal,
                _projectId,
                _accountingContexts[_i],
                _ruleset,
                _targetDecimals,
                _targetCurrency
            );
            // Increment the surplus with any remaining balance.
            if (_tokenSurplus > 0) surplus += _tokenSurplus;

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice Gets the amount that is surplusing for a token when measured from the specified ruleset.
    /// @dev This amount changes as the value of the balance changes in relation to the currency being used to measure the payout limit.
    /// @param _terminal The terminal for which the surplus is being calculated.
    /// @param _projectId The ID of the project to get surplus for.
    /// @param _accountingContext The accounting context of the token whose balance should contribute to the surplus being measured.
    /// @param _ruleset The ID of the ruleset to base the surplus on.
    /// @param _targetDecimals The number of decimals to include in the resulting fixed point number.
    /// @param _targetCurrency The currency that the reported surplus is expected to be in terms of.
    /// @return surplus The surplus of funds, as a fixed point number with 18 decimals.
    function _tokenSurplusFrom(
        IJBPaymentTerminal _terminal,
        uint256 _projectId,
        JBAccountingContext memory _accountingContext,
        JBRuleset memory _ruleset,
        uint256 _targetDecimals,
        uint256 _targetCurrency
    ) private view returns (uint256 surplus) {
        // Keep a reference to the balance.
        surplus = balanceOf[_terminal][_projectId][_accountingContext.token];

        // Adjust the decimals of the fixed point number if needed to have the correct decimals.
        surplus = _accountingContext.decimals == _targetDecimals
            ? surplus
            : JBFixedPointNumber.adjustDecimals(surplus, _accountingContext.decimals, _targetDecimals);

        // Add up all the balances.
        surplus = (surplus == 0 || _accountingContext.currency == _targetCurrency)
            ? surplus
            : PRBMath.mulDiv(
                surplus,
                10 ** _MAX_FIXED_POINT_FIDELITY, // Use _MAX_FIXED_POINT_FIDELITY to keep as much of the `_payoutLimitRemaining`'s fidelity as possible when converting.
                PRICES.pricePerUnitOf(
                    _projectId, _accountingContext.currency, _targetCurrency, _MAX_FIXED_POINT_FIDELITY
                )
            );

        // Get a reference to the payout limit during the ruleset for the token.
        JBCurrencyAmount[] memory _payoutLimits = IJBController(DIRECTORY.controllerOf(_projectId))
            .fundAccessLimits().payoutLimitsOf(
            _projectId, _ruleset.rulesetId, _terminal, _accountingContext.token
        );

        // Keep a reference to the payout limit being iterated on.
        JBCurrencyAmount memory _payoutLimit;

        // Keep a reference to the number of payout limits being iterated on.
        uint256 _numberOfPayoutLimits = _payoutLimits.length;

        // Loop through each payout limit to determine the cumulative normalized payout limit remaining.
        for (uint256 _i; _i < _numberOfPayoutLimits;) {
            _payoutLimit = _payoutLimits[_i];

            // Set the payout limit value to the amount still distributable during the ruleset.
            _payoutLimit.amount = _payoutLimit.amount
                - usedPayoutLimitOf[_terminal][_projectId][_accountingContext.token][_ruleset
                    .cycleNumber][_payoutLimit.currency];

            // Adjust the decimals of the fixed point number if needed to have the correct decimals.
            _payoutLimit.amount = _accountingContext.decimals == _targetDecimals
                ? _payoutLimit.amount
                : JBFixedPointNumber.adjustDecimals(
                    _payoutLimit.amount, _accountingContext.decimals, _targetDecimals
                );

            // Convert the _distributionRemaining to be in terms of the provided currency.
            _payoutLimit.amount = _payoutLimit.amount == 0
                || _payoutLimit.currency == _targetCurrency
                ? _payoutLimit.amount
                : PRBMath.mulDiv(
                    _payoutLimit.amount,
                    10 ** _MAX_FIXED_POINT_FIDELITY, // Use _MAX_FIXED_POINT_FIDELITY to keep as much of the `_payoutLimitRemaining`'s fidelity as possible when converting.
                    PRICES.pricePerUnitOf(
                        _projectId, _payoutLimit.currency, _targetCurrency, _MAX_FIXED_POINT_FIDELITY
                    )
                );

            // Decrement the balance until it reached zero.
            if (surplus > _payoutLimit.amount) {
                surplus -= _payoutLimit.amount;
            } else {
                return 0;
            }

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice Gets the amount that is currently surplusing across all of a project's terminals.
    /// @dev This amount changes as the value of the balances changes in relation to the currency being used to measure the project's payout limits.
    /// @param _projectId The ID of the project to get the total surplus for.
    /// @param _decimals The number of decimals that the fixed point surplus should include.
    /// @param _currency The currency that the surplus should be in terms of.
    /// @return surplus The total surplus of a project's funds.
    function _currentTotalSurplusOf(uint256 _projectId, uint256 _decimals, uint256 _currency)
        private
        view
        returns (uint256 surplus)
    {
        // Get a reference to the project's terminals.
        IJBPaymentTerminal[] memory _terminals = DIRECTORY.terminalsOf(_projectId);

        // Keep a reference to the number of termainls.
        uint256 _numberOfTerminals = _terminals.length;

        // Add the current ETH surplus for each terminal.
        for (uint256 _i; _i < _numberOfTerminals;) {
            surplus += _terminals[_i].currentSurplusOf(_projectId, _decimals, _currency);
            unchecked {
                ++_i;
            }
        }
    }
}
