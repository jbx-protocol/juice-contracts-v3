// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import './components/BaseNFT.sol';

/**
 * @notice ERC721
 */
contract NFToken is BaseNFT {
  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /**
   * @notice Creates the NFT contract.
   *
   * @param _name Token name.
   * @param _symbol Token symbol.
   * @param _baseUri Base URI, initially expected to point at generic, "unrevealed" metadata json.
   * @param _contractUri OpenSea-style contract metadata URI.
   * @param _maxSupply Max NFT supply.
   * @param _unitPrice Price per token expressed in Ether.
   * @param _mintAllowance Per-user mint cap.
   * @param _mintPeriodStart Start of the minting period in seconds.
   * @param _mintPeriodEnd End of the minting period in seconds.
   */
  constructor(
    string memory _name,
    string memory _symbol,
    string memory _baseUri,
    string memory _contractUri,
    uint256 _maxSupply,
    uint256 _unitPrice,
    uint256 _mintAllowance,
    uint256 _mintPeriodStart,
    uint256 _mintPeriodEnd
  ) {
    name = _name;
    symbol = _symbol;

    baseUri = _baseUri;
    contractUri = _contractUri;
    maxSupply = _maxSupply;
    unitPrice = _unitPrice;
    mintAllowance = _mintAllowance;
    mintPeriod = (_mintPeriodStart << 128) | _mintPeriodEnd;

    payoutReceiver = payable(msg.sender);
    royaltyReceiver = payable(msg.sender);

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(MINTER_ROLE, msg.sender);
    _grantRole(REVEALER_ROLE, msg.sender);
  }
}