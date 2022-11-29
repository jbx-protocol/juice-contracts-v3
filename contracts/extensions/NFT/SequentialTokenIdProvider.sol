// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/Strings.sol';

import './interfaces/ITokenIdProvider.sol';
import './interfaces/ITokenURIProvider.sol';

/**
 * @notice Not meant as a practical contract, this is a sample implementation of ITokenIdProvider and ITokenURIProvider.
 */
contract SequentialTokenIdProvider is ITokenIdProvider, ITokenURIProvider {
  using Strings for uint256;

  /**
   * @notice Error indicating the next token id exceeds max supply of the calling token.
   */
  error SUPPLY_EXCEEDED();

  string public baseUri;

  /**
   * @param _baseUri Root asset URI with trailing slash.
   */
  constructor(string memory _baseUri) {
    baseUri = _baseUri;
  }

  /**
   * @notice Returns a new token id by incrementing current supply, reverts is new id is greater than max supply. This method relies on parameters and does not dynamically check actual token values.
   *
   * @param _currentSupply Current token supply provided by caller, not checked.
   * @param _maxSupply Max token supply provided by caller, not checked.
   */
  function tokenId(
    uint256,
    uint256 _currentSupply,
    uint256 _maxSupply,
    address,
    uint256
  ) external returns (uint256 id) {
    unchecked {
      id = _currentSupply + 1;
    }

    if (id > _maxSupply) {
      revert SUPPLY_EXCEEDED();
    }
  }

  /**
   * @notice Appends token id to the base uri supplied in the contructor.
   *
   * @param _tokenId Token id
   */
  function tokenURI(uint256 _tokenId) public returns (string memory uri) {
    uri = string(abi.encodePacked(baseUri, _tokenId.toString()));
  }
}
