// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

/** 
  @member tokenId The ID of the position.
  @member allowPublicExtension A flag indicating whether or not the lock can be extended publicly by anyone.
*/
struct JBAllowPublicExtensionData {
  uint256 tokenId;
  bool allowPublicExtension;
}
