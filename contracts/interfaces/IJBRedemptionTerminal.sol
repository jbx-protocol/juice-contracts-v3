// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IJBRedemptionTerminal {
  function redeemTokensOf(
    address holder,
    uint256 projectId,
    address token,
    uint256 tokenCount,
    uint256 minReturnedTokens,
    address payable beneficiary,
    bytes calldata metadata
  ) external returns (uint256 reclaimAmount);
}
