// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

/**
 * @member tokenId The ID of the position.
 * @member beneficiary Address to transfer the locked amount to.
 */
struct JBUnlockData {
  uint256 tokenId;
  address beneficiary;
}
