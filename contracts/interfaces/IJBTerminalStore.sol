// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBRuleset} from "./../structs/JBRuleset.sol";
import {JBPayDelegateAllocation} from "./../structs/JBPayDelegateAllocation.sol";
import {JBRedeemDelegateAllocation} from "./../structs/JBRedeemDelegateAllocation.sol";
import {JBAccountingContext} from "./../structs/JBAccountingContext.sol";
import {JBTokenAmount} from "./../structs/JBTokenAmount.sol";
import {IJBDirectory} from "./IJBDirectory.sol";
import {IJBRulesets} from "./IJBRulesets.sol";
import {IJBPrices} from "./IJBPrices.sol";
import {IJBPaymentTerminal} from "./IJBPaymentTerminal.sol";

interface IJBTerminalStore {
    function RULESET_STORE() external view returns (IJBRulesets);

    function DIRECTORY() external view returns (IJBDirectory);

    function PRICES() external view returns (IJBPrices);

    function balanceOf(IJBPaymentTerminal terminal, uint256 projectId, address token)
        external
        view
        returns (uint256);

    function usedPayoutLimitOf(
        IJBPaymentTerminal terminal,
        uint256 projectId,
        address token,
        uint256 rulesetNumber,
        uint256 currency
    ) external view returns (uint256);

    function usedSurplusAllowanceOf(
        IJBPaymentTerminal terminal,
        uint256 projectId,
        address token,
        uint256 rulesetId,
        uint256 currency
    ) external view returns (uint256);

    function currentSurplusOf(
        IJBPaymentTerminal terminal,
        uint256 projectId,
        JBAccountingContext[] calldata tokenContexts,
        uint256 decimals,
        uint256 currency
    ) external view returns (uint256);

    function currentTotalSurplusOf(uint256 projectId, uint256 decimals, uint256 currency)
        external
        view
        returns (uint256);

    function currentReclaimableSurplusOf(
        IJBPaymentTerminal terminal,
        uint256 projectId,
        JBAccountingContext[] calldata tokenContexts,
        uint256 _decimals,
        uint256 _currency,
        uint256 tokenCount,
        bool useTotalSurplus
    ) external view returns (uint256);

    function currentReclaimableSurplusOf(
        uint256 projectId,
        uint256 tokenCount,
        uint256 totalSupply,
        uint256 surplus
    ) external view returns (uint256);

    function recordPaymentFrom(
        address payer,
        JBTokenAmount memory amount,
        uint256 projectId,
        address beneficiary,
        bytes calldata metadata
    )
        external
        returns (
            JBRuleset memory ruleset,
            uint256 tokenCount,
            JBPayDelegateAllocation[] memory delegateAllocations
        );

    function recordRedemptionFor(
        address holder,
        uint256 projectId,
        JBAccountingContext calldata tokenContext,
        JBAccountingContext[] calldata balanceTokenContexts,
        uint256 tokenCount,
        bytes calldata metadata
    )
        external
        returns (
            JBRuleset memory ruleset,
            uint256 reclaimAmount,
            JBRedeemDelegateAllocation[] memory delegateAllocations
        );

    function recordDistributionFor(
        uint256 projectId,
        JBAccountingContext calldata tokenContext,
        uint256 amount,
        uint256 currency
    ) external returns (JBRuleset memory ruleset, uint256 distributedAmount);

    function recordUsedAllowanceOf(
        uint256 projectId,
        JBAccountingContext calldata tokenContext,
        uint256 amount,
        uint256 currency
    ) external returns (JBRuleset memory ruleset, uint256 withdrawnAmount);

    function recordAddedBalanceFor(uint256 projectId, address token, uint256 amount) external;

    function recordMigration(uint256 projectId, address token) external returns (uint256 balance);
}
