// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IJBAllowanceTerminal {
  function useAllowanceOf(
    uint256 projectId,
    uint256 amount,
    uint256 currency,
    address token,
    uint256 minReturnedTokens,
    address payable beneficiary,
    string calldata memo
  ) external returns (uint256 netDistributedAmount);
}
