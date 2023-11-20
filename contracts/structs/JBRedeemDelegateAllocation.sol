// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBRedeemDelegate} from "../interfaces/IJBRedeemDelegate.sol";

/// @custom:member delegate A delegate contract to use for subsequent calls.
/// @custom:member amount The amount to send to the delegate.
/// @custom:member metadata Metadata to pass the delegate.
struct JBRedeemDelegateAllocation {
    IJBRedeemDelegate delegate;
    uint256 amount;
    bytes metadata;
}
