// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @notice A standard interface for external token uri calculation.
 */
interface ITokenURIProvider {
  function tokenURI(uint256 _tokenId) external view returns (string memory);
}
