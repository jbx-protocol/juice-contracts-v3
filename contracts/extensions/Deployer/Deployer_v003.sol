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
  bytes32 internal constant deployDutchAuctionKey =
    keccak256(abi.encodePacked('deployDutchAuctionSplitter'));
  bytes32 internal constant deployEnglishAuctionKey =
    keccak256(abi.encodePacked('deployEnglishAuction'));
  DutchAuctionHouse internal dutchAuctionSource;
  EnglishAuctionHouse internal englishAuctionSource;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    DutchAuctionHouse _dutchAuctionSource,
    EnglishAuctionHouse _englishAuctionSource
  ) public reinitializer(3) {
    __Ownable_init();
    __UUPSUpgradeable_init();

    dutchAuctionSource = _dutchAuctionSource;
    englishAuctionSource = _englishAuctionSource;

    prices[deployDutchAuctionKey] = 1000000000000000; // 0.001 eth
    prices[deployEnglishAuctionKey] = 1000000000000000; // 0.001 eth
  }

  function deployDutchAuction(
    uint256 _projectId,
    IJBPaymentTerminal _feeReceiver,
    uint256 _feeRate,
    bool _allowPublicAuctions,
    uint256 _periodDuration,
    address _owner,
    IJBDirectory _directory
  ) external payable returns (address auction) {
    validatePayment(deployDutchAuctionKey);

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
  ) external payable returns (address auction) {
    validatePayment(deployEnglishAuctionKey);

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
