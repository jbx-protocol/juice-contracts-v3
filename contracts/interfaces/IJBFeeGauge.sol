// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IJBFeeGauge {
  function currentDiscountFor(uint256 projectId) external view returns (uint256);
}
