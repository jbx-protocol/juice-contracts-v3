// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface IJBVeTokenUriResolver {
  /**
   * @notice Provides the metadata for the storefront
   */
  function contractURI() external view returns (string memory);

  /**
   * @notice Computes the metadata url.
   *
   * @param _tokenId TokenId of the Banny
   * @param _amount Lock Amount.
   * @param _duration Lock time in seconds.
   * @param _lockedUntil Total lock-in period.
   * @param _lockDurationOptions The options that the duration can be.
   *
   * @return The metadata url.
   */
  function tokenURI(
    uint256 _tokenId,
    uint256 _amount,
    uint256 _duration,
    uint256 _lockedUntil,
    uint256[] memory _lockDurationOptions
  ) external view returns (string memory);
}
