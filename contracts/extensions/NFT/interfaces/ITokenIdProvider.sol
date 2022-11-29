// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITokenIdProvider {
  function tokenId(
    uint256 _amount,
    uint256 _currentSupply,
    uint256 _maxSupply,
    address _account,
    uint256 _accountBalance
  ) external view returns (uint256);
}
