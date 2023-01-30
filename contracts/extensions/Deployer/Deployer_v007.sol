// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../Auctions/DutchAuction.sol';
import '../Auctions/EnglishAuction.sol';
import '../Auctions/FixedPriceSale.sol';
import '../NFT/DutchAuctionMachine.sol';
import '../NFT/EnglishAuctionMachine.sol';
import '../NFT/NFUEdition.sol';
import '../NFT/NFUToken.sol';
import '../NFT/TraitToken.sol';
import '../TokenLiquidator.sol';

import './Deployer_v006.sol';
import './Factories/AuctionMachineFactory.sol';
import './Factories/TraitTokenFactory.sol';
import './Factories/NFUEditionFactory.sol';

/**
 * @notice This version of the deployer adds the ability to deploy Dutch and English perpetual auctions for a specific NFT.
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Deployer_v007 is Deployer_v006 {
  bytes32 internal constant deployDutchAuctionMachineKey =
    keccak256(abi.encodePacked('deployDutchAuctionMachine'));
  bytes32 internal constant deployEnglishAuctionMachineKey =
    keccak256(abi.encodePacked('deployEnglishAuctionMachine'));
  bytes32 internal constant deployTraitTokenKey = keccak256(abi.encodePacked('deployTraitToken'));
  bytes32 internal constant deployNFUEditionKey = keccak256(abi.encodePacked('deployNFUEdition'));

  DutchAuctionMachine internal dutchAuctionMachineSource;
  EnglishAuctionMachine internal englishAuctionMachineSource;
  TraitToken internal traitTokenSource;
  NFUEdition internal nfuEditionSource;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    DutchAuctionHouse _dutchAuctionSource,
    EnglishAuctionHouse _englishAuctionSource,
    FixedPriceSale _fixedPriceSaleSource,
    NFUToken _nfuTokenSource,
    ITokenLiquidator _tokenLiquidator,
    DutchAuctionMachine _dutchAuctionMachineSource,
    EnglishAuctionMachine _englishAuctionMachineSource,
    TraitToken _traitTokenSource,
    NFUEdition _nfuEditionSource
  ) public virtual reinitializer(7) {
    __Ownable_init();
    __UUPSUpgradeable_init();

    dutchAuctionSource = _dutchAuctionSource;
    englishAuctionSource = _englishAuctionSource;
    fixedPriceSaleSource = _fixedPriceSaleSource;
    nfuTokenSource = _nfuTokenSource;
    tokenLiquidator = _tokenLiquidator;
    dutchAuctionMachineSource = _dutchAuctionMachineSource;
    englishAuctionMachineSource = _englishAuctionMachineSource;
    traitTokenSource = _traitTokenSource;
    nfuEditionSource = _nfuEditionSource;

    prices[deployDutchAuctionMachineKey] = 1000000000000000; // 0.001 eth
    prices[deployEnglishAuctionMachineKey] = 1000000000000000; // 0.001 eth
    prices[deployTraitTokenKey] = 1000000000000000; // 0.001 eth
    prices[deployNFUEditionKey] = 1000000000000000; // 0.001 eth
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
  ) external payable returns (address machine) {
    validatePayment(deployDutchAuctionMachineKey);

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
  ) external payable returns (address machine) {
    validatePayment(deployEnglishAuctionMachineKey);

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

  function deployTraitToken(
    address _owner,
    string memory _name,
    string memory _symbol,
    string memory _baseUri,
    string memory _contractUri,
    uint256 _maxSupply,
    uint256 _unitPrice,
    uint256 _mintAllowance
  ) external payable returns (address token) {
    validatePayment(deployTraitTokenKey);

    token = TraitTokenFactory.createTraitToken(
      address(traitTokenSource),
      _owner,
      _name,
      _symbol,
      _baseUri,
      _contractUri,
      _maxSupply,
      _unitPrice,
      _mintAllowance
    );

    emit Deployment('TraitToken', token);
  }

  function deployNFUEdition(
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
  ) external payable returns (address token) {
    validatePayment(deployNFUEditionKey);

    token = NFUEditionFactory.createNFUEdition(
      address(nfuEditionSource),
      _owner,
      _name,
      _symbol,
      _baseUri,
      _contractUri,
      _maxSupply,
      _unitPrice,
      _mintAllowance
    );

    emit Deployment('NFUEdition', token);
  }
}
