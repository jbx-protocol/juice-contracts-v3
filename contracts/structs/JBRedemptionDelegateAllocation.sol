// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBRedemptionDelegate} from '../interfaces/IJBRedemptionDelegate.sol';

/// @custom:member delegate A delegate contract to use for subsequent calls.
/// @custom:member amount The amount to send to the delegate.
struct JBRedemptionDelegateAllocation {
  IJBRedemptionDelegate delegate;
  uint256 amount;
}
