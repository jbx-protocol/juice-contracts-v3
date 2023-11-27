// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBRedeemHook} from "../interfaces/IJBRedeemHook.sol";

/// @custom:member hook A redeem hook contract to use for subsequent calls.
/// @custom:member amount The amount to send to the hook.
/// @custom:member metadata Metadata to pass the hook.
struct JBRedeemHookPayload {
    IJBRedeemHook hook;
    uint256 amount;
    bytes metadata;
}
