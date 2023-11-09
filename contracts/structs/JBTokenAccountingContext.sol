// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member decimals The number of decimals expected in a token's fixed point accounting.
/// @custom:member currency The currency a token is accounting in.
struct JBTokenAccountingContext {
  uint8 decimals;
  uint32 currency;
}
