// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';

import './IOperatorFilter.sol';

/**
 * @notice NFT filter keeps a registry of addresses and code hashes that an NFT contract may use to prevent token mint and transfer operations.
 *
 * @dev Based on https://github.com/archipelago-art/erc721-operator-filter/blob/main/contracts/BlacklistOperatorFilter.sol
 */
contract OperatorFilter is Ownable, IOperatorFilter {
  mapping(address => bool) public blockedAddresses;
  mapping(bytes32 => bool) public blockedCodeHashes;

  function mayTransfer(address _operator) external view override returns (bool) {
    if (blockedAddresses[_operator] || blockedCodeHashes[_operator.codehash]) {
      return false;
    }

    return true;
  }

  /**
   * Registers an address to block from performing NFT operations.
   */
  function registerAddress(address _account, bool _blocked) external override onlyOwner {
    if (!_blocked) {
      delete blockedAddresses[_account];
    }

    blockedAddresses[_account] = _blocked;
  }

  /**
   * Registers a contract codehash (`address.codehash`) to prevent NFT operations for a range of contracts rather than registring one address at a time.
   */
  function registerCodeHash(bytes32 _codeHash, bool _blocked) external override onlyOwner {
    if (_codeHash != keccak256('')) {
      blockedCodeHashes[_codeHash] = _blocked;
    }
  }
}
