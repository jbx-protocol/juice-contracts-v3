// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {JBAccountingContext} from './../structs/JBAccountingContext.sol';

interface IJBCustomPayToken is IERC165 {
  function decimals() external view returns (uint256);

  function beforeTransferTo(
    uint256 projectId,
    address to,
    uint256 amount,
    JBAccountingContext calldata accountingContext
  ) external;

  function transferFor(
    uint256 projectId,
    address from,
    address to,
    uint256 amount,
    JBAccountingContext calldata accountingContext
  ) external;

  function cancelTransferTo(
    uint256 projectId,
    address to,
    uint256 amount,
    JBAccountingContext calldata accountingContext
  ) external;
}
