// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import '../../interfaces/IJBDirectory.sol';
import './components/BaseNFT.sol';

contract NFUToken is BaseNFT, Initializable {
  //*********************************************************************//
  // -------------------------- initializer ---------------------------- //
  //*********************************************************************//

  /**
   * @notice Creates the NFT contract.
   *
   * @param _name Token name.
   * @param _symbol Token symbol.
   * @param _baseUri Base URI, initially expected to point at generic, "unrevealed" metadata json.
   * @param _contractUri OpenSea-style contract metadata URI.
   * @param _jbxProjectId Juicebox project id that will be paid the proceeds of the sale.
   * @param _jbxDirectory Juicebox directory to determine payment destination.
   * @param _maxSupply Max NFT supply.
   * @param _unitPrice Price per token expressed in Ether.
   * @param _mintAllowance Per-user mint cap.
   * @param _mintPeriodStart Start of the minting period in seconds.
   * @param _mintPeriodEnd End of the minting period in seconds.
   */
  function initialize(
    string memory _name,
    string memory _symbol,
    string memory _baseUri,
    string memory _contractUri,
    uint256 _jbxProjectId,
    IJBDirectory _jbxDirectory,
    uint256 _maxSupply,
    uint256 _unitPrice,
    uint256 _mintAllowance,
    uint128 _mintPeriodStart,
    uint128 _mintPeriodEnd
  ) public initializer {
    name = _name;
    symbol = _symbol;

    baseUri = _baseUri;
    contractUri = _contractUri;
    jbxDirectory = _jbxDirectory;
    jbxProjectId = _jbxProjectId;
    maxSupply = _maxSupply;
    unitPrice = _unitPrice;
    mintAllowance = _mintAllowance;
    mintPeriodStart = _mintPeriodStart;
    mintPeriodEnd = _mintPeriodEnd;

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(MINTER_ROLE, msg.sender);
    _grantRole(REVEALER_ROLE, msg.sender);
  }
}
