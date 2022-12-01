// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @notice A common interface for external token id calculation. This is intended to be used during the mint of an ERC721 token.
 *
 * @param _amount Amount being paid for the mint.
 * @param  _currentSupply Token current supply.
 * @param  _maxSupply Token max supply.
 * @param  _account Beneficiary account of the mint operation, the one that will own the token.
 * @param  _accountBalance Current account token balance.
 */
interface ITokenIdProvider {
  function tokenId(
    uint256 _amount,
    uint256 _currentSupply,
    uint256 _maxSupply,
    address _account,
    uint256 _accountBalance
  ) external returns (uint256);
}
