// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

/**
 * @member tokenId The ID of the position.
 * @member updatedDuration The updated duration of the lock.
 */
struct JBLockExtensionData {
  uint256 tokenId;
  uint256 updatedDuration;
}
