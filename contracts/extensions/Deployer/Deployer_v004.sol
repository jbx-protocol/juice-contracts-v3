// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../Auctions/DutchAuction.sol';
import '../Auctions/EnglishAuction.sol';
import '../NFT/NFUToken.sol';
import './Deployer_v003.sol';
import './NFUTokenFactory.sol';

/**
 * @notice This version of the deployer adds the ability to create ERC721 NFTs from a reusable instance.
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Deployer_v004 is Deployer_v003 {
  NFUToken internal nfuTokenSource;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    DutchAuctionHouse _dutchAuctionSource,
    EnglishAuctionHouse _englishAuctionSource,
    NFUToken _nfuTokenSource
  ) public virtual reinitializer(4) {
    __Ownable_init();
    __UUPSUpgradeable_init();

    dutchAuctionSource = _dutchAuctionSource;
    englishAuctionSource = _englishAuctionSource;
    nfuTokenSource = _nfuTokenSource;
  }

  function deployNFUToken(
    address _owner,
    string memory _name,
    string memory _symbol,
    string memory _baseUri,
    string memory _contractUri,
    uint256 _jbxProjectId,
    IJBDirectory _jbxDirectory,
    uint256 _maxSupply,
    uint256 _unitPrice,
    uint256 _mintAllowance
  ) external returns (address token) {
    token = NFUTokenFactory.createNFUToken(
      address(nfuTokenSource),
      _owner,
      _name,
      _symbol,
      _baseUri,
      _contractUri,
      _jbxProjectId,
      _jbxDirectory,
      _maxSupply,
      _unitPrice,
      _mintAllowance
    );
    emit Deployment('NFUToken', token);
  }
}
