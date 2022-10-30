// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../Auctions/DutchAuction.sol';
import '../Auctions/EnglishAuction.sol';
import './Deployer_v002.sol';
import './Factories/AuctionsFactory.sol';

/**
 * @notice This version of the deployer adds the ability to create DutchAuctionHouse and EnglishAuctionHouse contracts.
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Deployer_v003 is Deployer_v002 {
  DutchAuctionHouse internal dutchAuctionSource;
  EnglishAuctionHouse internal englishAuctionSource;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    DutchAuctionHouse _dutchAuctionSource,
    EnglishAuctionHouse _englishAuctionSource
  ) public virtual reinitializer(3) {
    __Ownable_init();
    __UUPSUpgradeable_init();

    dutchAuctionSource = _dutchAuctionSource;
    englishAuctionSource = _englishAuctionSource;
  }

  function deployDutchAuction(
    uint256 _projectId,
    IJBPaymentTerminal _feeReceiver,
    uint256 _feeRate,
    bool _allowPublicAuctions,
    uint256 _periodDuration,
    address _owner,
    IJBDirectory _directory
  ) external returns (address auction) {
    auction = AuctionsFactory.createDutchAuction(
      address(dutchAuctionSource),
      _projectId,
      _feeReceiver,
      _feeRate,
      _allowPublicAuctions,
      _periodDuration,
      _owner,
      _directory
    );

    emit Deployment('DutchAuctionHouse', auction);
  }

  function deployEnglishAuction(
    uint256 _projectId,
    IJBPaymentTerminal _feeReceiver,
    uint256 _feeRate,
    bool _allowPublicAuctions,
    address _owner,
    IJBDirectory _directory
  ) external returns (address auction) {
    auction = AuctionsFactory.createEnglishAuction(
      address(englishAuctionSource),
      _projectId,
      _feeReceiver,
      _feeRate,
      _allowPublicAuctions,
      _owner,
      _directory
    );

    emit Deployment('EnglishAuctionHouse', auction);
  }
}
