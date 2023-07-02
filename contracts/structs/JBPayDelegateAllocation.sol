// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPayDelegate} from '../interfaces/IJBPayDelegate.sol';

/// @custom:member delegate A delegate contract to use for subsequent calls.
/// @custom:member amount The amount to send to the delegate.
struct JBPayDelegateAllocation {
  IJBPayDelegate delegate;
  uint256 amount;
}
