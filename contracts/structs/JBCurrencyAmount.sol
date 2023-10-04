// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member value The amount of tokens that was paid, as a fixed point number.
/// @custom:member currency The expected currency of the value.
struct JBCurrencyAmount {
  uint256 value;
  uint256 currency;
}
