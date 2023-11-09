// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {JBTokenAccountingContext} from '../structs/JBTokenAccountingContext.sol';

interface IJBPaymentTerminal is IERC165 {
  function accountingContextForTokenOf(
    uint256 projectId,
    address token
  ) external view returns (JBTokenAccountingContext memory);

  function currentEthOverflowOf(uint256 projectId) external view returns (uint256);

  function pay(
    uint256 projectId,
    uint256 amount,
    address token,
    address beneficiary,
    uint256 minReturnedTokens,
    bytes calldata metadata
  ) external payable returns (uint256 beneficiaryTokenCount);

  function addToBalanceOf(
    uint256 projectId,
    uint256 amount,
    address token,
    bool shouldRefundHeldFees,
    bytes calldata metadata
  ) external payable;
}
