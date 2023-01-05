// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../Auctions/DutchAuction.sol';
import '../Auctions/EnglishAuction.sol';
import '../Auctions/FixedPriceSale.sol';
import '../NFT/NFUToken.sol';
import './Deployer_v003.sol';
import './Factories/NFUTokenFactory.sol';

/**
 * @notice This version of the deployer adds the ability to create ERC721 NFTs from a reusable instance.
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Deployer_v004 is Deployer_v003 {
  bytes32 internal constant deployNFUTokenKey = keccak256(abi.encodePacked('deployNFUToken'));
  NFUToken internal nfuTokenSource;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev This function clashes with initialize in Deployer_v001, for this reason instead of having typed arguments, they're addresses.
   */
  function initialize(
    DutchAuctionHouse _dutchAuctionSource,
    EnglishAuctionHouse _englishAuctionSource,
    FixedPriceSale _fixedPriceSaleSource,
    NFUToken _nfuTokenSource
  ) public virtual reinitializer(4) {
    __Ownable_init();
    __UUPSUpgradeable_init();

    dutchAuctionSource = _dutchAuctionSource;
    englishAuctionSource = _englishAuctionSource;
    fixedPriceSaleSource = _fixedPriceSaleSource;
    nfuTokenSource = _nfuTokenSource;

    prices[deployNFUTokenKey] = 1000000000000000; // 0.001 eth
  }

  /**
   * @dev This creates a token that can be minted immediately, to discourage this, unitPrice can be set high, then mint period can be defined before setting price to a "reasonable" value.
   */
  function deployNFUToken(
    address _owner,
    string memory _name,
    string memory _symbol,
    string memory _baseUri,
    string memory _contractUri,
    uint256 _maxSupply,
    uint256 _unitPrice,
    uint256 _mintAllowance
  ) external payable returns (address token) {
    validatePayment(deployNFUTokenKey);

    token = NFUTokenFactory.createNFUToken(
      address(nfuTokenSource),
      _owner,
      _name,
      _symbol,
      _baseUri,
      _contractUri,
      _maxSupply,
      _unitPrice,
      _mintAllowance
    );

    emit Deployment('NFUToken', token);
  }
}
