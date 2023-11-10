// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {JBTokenAccountingContext} from '../structs/JBTokenAccountingContext.sol';

interface IJBPaymentTerminal is IERC165 {
  function accountingContextForTokenOf(
    uint256 projectId,
    address token
  ) external view returns (JBTokenAccountingContext memory);

  function tokenContextsAcceptedBy(
    uint256 projectId
  ) external view returns (JBTokenAccountingContext[] memory);

  function currentOverflowOf(
    uint256 projectId,
    uint256 decimals,
    uint256 currency
  ) external view returns (uint256);

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

  function setTokenAccountingContextFor(
    uint256 projectId,
    address token,
    uint8 decimals,
    uint32 currency,
    uint8 standard
  ) external;
}
