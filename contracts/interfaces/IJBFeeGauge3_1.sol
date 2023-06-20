// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './../enums/JBFeeType.sol';

interface IJBFeeGauge3_1 {
  function currentDiscountFor(
    uint256 _projectId,
    JBFeeType _feeType
  ) external view returns (uint256);
}
