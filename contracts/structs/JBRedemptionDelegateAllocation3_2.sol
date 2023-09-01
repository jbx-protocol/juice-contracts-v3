// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBRedemptionDelegate3_2} from '../interfaces/IJBRedemptionDelegate3_2.sol';

/// @custom:member delegate A delegate contract to use for subsequent calls.
/// @custom:member amount The amount to send to the delegate.
/// @custom:member metadata Metadata to pass the delegate.
struct JBRedemptionDelegateAllocation3_2 {
  IJBRedemptionDelegate3_2 delegate;
  uint256 amount;
  bytes metadata;
}
