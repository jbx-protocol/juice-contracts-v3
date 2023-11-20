// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBAccountingContext} from "../../structs/JBAccountingContext.sol";
import {JBAccountingContextConfig} from "../../structs/JBAccountingContextConfig.sol";
import {JBDidPayData3_1_1} from "../../structs/JBDidPayData3_1_1.sol";

import {IJBPayDelegate3_1_1} from "../../interfaces/IJBPayDelegate3_1_1.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IJBPaymentTerminal is IERC165 {
     event Migrate(
        uint256 indexed projectId,
        address indexed token,
        IJBPaymentTerminal indexed to,
        uint256 amount,
        address caller
    );

    event AddToBalance(
        uint256 indexed projectId,
        uint256 amount,
        uint256 refundedFees,
        string memo,
        bytes metadata,
        address caller
    );

    event SetAccountingContext(
        uint256 indexed projectId,
        address indexed token,
        JBAccountingContext context,
        address caller
    );

    event Pay(
        uint256 indexed fundingCycleConfiguration,
        uint256 indexed fundingCycleNumber,
        uint256 indexed projectId,
        address payer,
        address beneficiary,
        uint256 amount,
        uint256 beneficiaryTokenCount,
        string memo,
        bytes metadata,
        address caller
    );

    event DelegateDidPay(
        IJBPayDelegate3_1_1 indexed delegate,
        JBDidPayData3_1_1 data,
        uint256 delegatedAmount,
        address caller
    );

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

    function migrateBalanceOf(uint256 projectId, address token, IJBPaymentTerminal to)
        external
        returns (uint256 balance);

    function setAccountingContextsFor(
        uint256 projectId,
        JBAccountingContextConfig[] calldata accountingContexts
    ) external;

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
}
