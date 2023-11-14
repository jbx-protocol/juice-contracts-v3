// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {JBAccountingContext} from "../structs/JBAccountingContext.sol";
import {JBAccountingContextConfig} from "../structs/JBAccountingContextConfig.sol";

interface IJBPaymentTerminal is IERC165 {
    function accountingContextForTokenOf(uint256 projectId, address token)
        external
        view
        returns (JBAccountingContext memory);

    function accountingContextsOf(uint256 projectId)
        external
        view
        returns (JBAccountingContext[] memory);

    function currentOverflowOf(uint256 projectId, uint256 decimals, uint256 currency)
        external
        view
        returns (uint256);

    function pay(
        uint256 projectId,
        address token,
        uint256 amount,
        address beneficiary,
        uint256 minReturnedTokens,
        string calldata memo,
        bytes calldata metadata
    ) external payable returns (uint256 beneficiaryTokenCount);

    function addToBalanceOf(
        uint256 projectId,
        address token,
        uint256 amount,
        bool shouldRefundHeldFees,
        string calldata memo,
        bytes calldata metadata
    ) external payable;

    function distributePayoutsOf(
        uint256 projectId,
        address token,
        uint256 amount,
        uint256 currency,
        uint256 minReturnedTokens
    ) external returns (uint256 netLeftoverDistributionAmount);

    function useAllowanceOf(
        uint256 projectId,
        address token,
        uint256 amount,
        uint256 currency,
        uint256 minReturnedTokens,
        address payable beneficiary,
        string calldata memo
    ) external returns (uint256 netDistributedAmount);

    function redeemTokensOf(
        address holder,
        uint256 projectId,
        address token,
        uint256 count,
        uint256 minReclaimed,
        address payable beneficiary,
        bytes calldata metadata
    ) external returns (uint256 reclaimAmount);

    function migrateBalanceOf(uint256 projectId, address token, IJBPaymentTerminal to)
        external
        returns (uint256 balance);

    function setAccountingContextsFor(
        uint256 projectId,
        JBAccountingContextConfig[] calldata accountingContexts
    ) external;
}
