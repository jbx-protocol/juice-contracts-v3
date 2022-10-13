// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';

import './IOperatorFilter.sol';

/**
 * @notice NFT filter keeps a registry of addresses and code hashes that an NFT contract may use to prevent token mint and transfer operations.
 *
 * @dev Based on https://github.com/archipelago-art/erc721-operator-filter/blob/main/contracts/BlacklistOperatorFilter.sol
 */
contract BlacklistOperatorFilter is Ownable, IOperatorFilter {
  mapping(address => bool) public blockedAddresses;
  mapping(bytes32 => bool) public blockedCodeHashes;

  function mayTransfer(address _operator) external view override returns (bool) {
    if (blockedAddresses[_operator] || blockedCodeHashes[_operator.codehash]) {
      return false;
    }

    return true;
  }

  function registerAddress(address _account, bool _blocked) external override onlyOwner {
    blockedAddresses[_account] = _blocked;
  }

  function registerCodeHash(bytes32 _codeHash, bool _blocked) external override onlyOwner {
    if (_codeHash != keccak256('')) {
      blockedCodeHashes[_codeHash] = _blocked;
    }
  }
}
