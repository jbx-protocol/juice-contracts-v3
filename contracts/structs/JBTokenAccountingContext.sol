// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member decimals The number of decimals expected in a token's fixed point accounting.
/// @custom:member currency The currency a token is accounting in.
/// @custom:member payoutSplitsGroup The splits group under which payouts of this token are referenced.
struct JBTokenAccountingContext {
  uint8 decimals;
  uint32 currency;
  uint216 payoutSplitsGroup;
}
