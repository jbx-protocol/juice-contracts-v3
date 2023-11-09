// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IJBPayoutTerminal3_1 {
  function distributePayoutsOf(
    uint256 projectId,
    address token,
    uint256 amount,
    uint256 currency,
    uint256 minReturnedTokens
  ) external returns (uint256 netLeftoverDistributionAmount);
}
