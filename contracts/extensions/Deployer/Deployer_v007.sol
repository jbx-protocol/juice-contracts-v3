// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../Auctions/DutchAuction.sol';
import '../Auctions/EnglishAuction.sol';
import '../NFT/DutchAuctionMachine.sol';
import '../NFT/EnglishAuctionMachine.sol';
import '../NFT/NFUToken.sol';
import '../TokenLiquidator.sol';

import './Deployer_v006.sol';
import './Factories/AuctionMachineFactory.sol';

/**
 * @notice This version of the deployer adds the ability to deploy Dutch and English perpetual auctions for a specific NFT.
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Deployer_v007 is Deployer_v006 {
  DutchAuctionMachine internal dutchAuctionMachineSource;
  EnglishAuctionMachine internal englishAuctionMachineSource;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    DutchAuctionHouse _dutchAuctionSource,
    EnglishAuctionHouse _englishAuctionSource,
    NFUToken _nfuTokenSource,
    ITokenLiquidator _tokenLiquidator,
    DutchAuctionMachine _dutchAuctionMachineSource,
    EnglishAuctionMachine _englishAuctionMachineSource
  ) public virtual reinitializer(7) {
    __Ownable_init();
    __UUPSUpgradeable_init();

    dutchAuctionSource = _dutchAuctionSource;
    englishAuctionSource = _englishAuctionSource;
    nfuTokenSource = _nfuTokenSource;
    tokenLiquidator = _tokenLiquidator;
    dutchAuctionMachineSource = _dutchAuctionMachineSource;
    englishAuctionMachineSource = _englishAuctionMachineSource;
  }

  /**
   * @param _maxAuctions Maximum number of auctions to perform automatically, 0 for no limit.
   * @param _auctionDuration Auction duration in seconds.
   * @param _periodDuration Price reduction period in seconds.
   * @param _maxPriceMultiplier Dutch auction opening price multiplier. NFT contract must expose price via `unitPrice()`.
   * @param _projectId Juicebox project id which should recieve auction proceeds.
   * @param _jbxDirectory Juicebox directory contract
   * @param _token ERC721 token the Auction machine will have minting privileges on.
   * @param _owner Auction machine admin.
   */
  function deployDutchAuctionMachine(
    uint256 _maxAuctions,
    uint256 _auctionDuration,
    uint256 _periodDuration,
    uint256 _maxPriceMultiplier,
    uint256 _projectId,
    IJBDirectory _jbxDirectory,
    address _token,
    address _owner
  ) external returns (address machine) {
    machine = AuctionMachineFactory.createDutchAuctionMachine(
      address(dutchAuctionMachineSource),
      _maxAuctions,
      _auctionDuration,
      _periodDuration,
      _maxPriceMultiplier,
      _projectId,
      _jbxDirectory,
      _token,
      _owner
    );
    emit Deployment('DutchAuctionMachine', machine);
  }

  /**
   * @param _maxAuctions Maximum number of auctions to perform automatically, 0 for no limit.
   * @param _auctionDuration Auction duration in seconds.
   * @param _projectId Juicebox project id, used to transfer auction proceeds.
   * @param _jbxDirectory Juicebox directory, used to transfer auction proceeds to the correct terminal.
   * @param _token Token contract to operate on.
   * @param _owner Auction machine admin.
   */
  function deployEnglishAuctionMachine(
    uint256 _maxAuctions,
    uint256 _auctionDuration,
    uint256 _projectId,
    IJBDirectory _jbxDirectory,
    address _token,
    address _owner
  ) external returns (address machine) {
    machine = AuctionMachineFactory.createEnglishAuctionMachine(
      address(englishAuctionMachineSource),
      _maxAuctions,
      _auctionDuration,
      _projectId,
      _jbxDirectory,
      _token,
      _owner
    );
    emit Deployment('EnglishAuctionMachine', machine);
  }
}
