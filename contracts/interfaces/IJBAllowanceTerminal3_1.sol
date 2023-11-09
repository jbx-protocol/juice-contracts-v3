// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IJBAllowanceTerminal3_1 {
  function useAllowanceOf(
    uint256 projectId,
    address token,
    uint256 amount,
    uint256 currency,
    uint256 minReturnedTokens,
    address payable beneficiary,
    string calldata memo
  ) external returns (uint256 netDistributedAmount);
}
