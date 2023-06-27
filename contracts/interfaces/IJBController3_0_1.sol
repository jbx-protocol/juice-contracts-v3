// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IJBController3_0_1 {
  function reservedTokenBalanceOf(uint256 projectId) external view returns (uint256);

  function totalOutstandingTokensOf(uint256 projectId) external view returns (uint256);
}
