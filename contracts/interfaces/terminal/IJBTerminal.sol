// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBAccountingContext} from "../../structs/JBAccountingContext.sol";
import {JBAccountingContextConfig} from "../../structs/JBAccountingContextConfig.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IJBTerminal is IERC165 {
     event Migrate(
        uint256 indexed projectId,
        address indexed token,
        IJBTerminal indexed to,
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

    function addToBalanceOf(
        uint256 projectId,
        address token,
        uint256 amount,
        bool shouldRefundHeldFees,
        string calldata memo,
        bytes calldata metadata
    ) external payable;

    function migrateBalanceOf(uint256 projectId, address token, IJBTerminal to)
        external
        returns (uint256 balance);

    function setAccountingContextsFor(
        uint256 projectId,
        JBAccountingContextConfig[] calldata accountingContexts
    ) external;
}
