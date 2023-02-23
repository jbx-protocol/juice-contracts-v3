// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import '../../../interfaces/IJBPayoutRedemptionPaymentTerminal.sol';

/**
 * @member tokenId Banny Id.
 * @member token The token to be reclaimed from the redemption.
 * @member minReturnedTokens The minimum amount of terminal tokens expected in return, as a fixed point number with the same amount of decimals as the terminal.
 * @member beneficiary The address to send the terminal tokens to.
 * @member memo A memo to pass along to the emitted event.
 * @member metadata Bytes to send along to the data source and delegate, if provided.
 */
struct JBRedeemData {
  uint256 tokenId;
  address token;
  uint256 minReturnedTokens;
  address payable beneficiary;
  string memo;
  bytes metadata;
  IJBRedemptionTerminal terminal;
}
