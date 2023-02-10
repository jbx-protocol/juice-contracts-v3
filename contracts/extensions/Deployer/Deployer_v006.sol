// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../Auctions/DutchAuction.sol';
import '../Auctions/EnglishAuction.sol';
import '../Auctions/FixedPriceSale.sol';
import '../NFT/NFUToken.sol';
import '../TokenLiquidator.sol';
import './Deployer_v005.sol';
import './Factories/NFTRewardDataSourceFactory.sol';

/**
 * @notice This version of the deployer adds the ability to deploy NFTRewardDataSourceDelegate instances and related contracts to allow projects to issue NFTs to contributing accounts.
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Deployer_v006 is Deployer_v005 {
  bytes32 internal constant deployOpenTieredTokenUriResolverKey =
    keccak256(abi.encodePacked('deployOpenTieredTokenUriResolver'));
  bytes32 internal constant deployOpenTieredPriceResolverKey =
    keccak256(abi.encodePacked('deployOpenTieredPriceResolver'));
  bytes32 internal constant deployTieredTokenUriResolverKey =
    keccak256(abi.encodePacked('deployTieredTokenUriResolver'));
  bytes32 internal constant deployTieredPriceResolverKey =
    keccak256(abi.encodePacked('deployTieredPriceResolver'));
  bytes32 internal constant deployNFTRewardDataSourceKey =
    keccak256(abi.encodePacked('deployNFTRewardDataSource'));

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    DutchAuctionHouse _dutchAuctionSource,
    EnglishAuctionHouse _englishAuctionSource,
    FixedPriceSale _fixedPriceSaleSource,
    NFUToken _nfuTokenSource,
    ITokenLiquidator _tokenLiquidator
  ) public virtual override reinitializer(6) {
    __Ownable_init();
    __UUPSUpgradeable_init();

    dutchAuctionSource = _dutchAuctionSource;
    englishAuctionSource = _englishAuctionSource;
    fixedPriceSaleSource = _fixedPriceSaleSource;
    nfuTokenSource = _nfuTokenSource;
    tokenLiquidator = _tokenLiquidator;

    prices[deployOpenTieredTokenUriResolverKey] = baseFee;
    prices[deployOpenTieredPriceResolverKey] = baseFee;
    prices[deployTieredTokenUriResolverKey] = baseFee;
    prices[deployTieredPriceResolverKey] = baseFee;
    prices[deployNFTRewardDataSourceKey] = baseFee;
  }

  function deployOpenTieredTokenUriResolver(
    string memory _baseUri
  ) external payable returns (address resolver) {
    validatePayment(deployOpenTieredTokenUriResolverKey);
    resolver = NFTRewardDataSourceFactory.createOpenTieredTokenUriResolver(_baseUri);
    emit Deployment('OpenTieredTokenUriResolver', resolver);
  }

  function deployOpenTieredPriceResolver(
    address _contributionToken,
    OpenRewardTier[] memory _tiers
  ) external payable returns (address resolver) {
    validatePayment(deployOpenTieredPriceResolverKey);
    resolver = NFTRewardDataSourceFactory.createOpenTieredPriceResolver(_contributionToken, _tiers);
    emit Deployment('OpenTieredPriceResolver', resolver);
  }

  function deployTieredTokenUriResolver(
    string memory _baseUri,
    uint256[] memory _idRange
  ) external payable returns (address resolver) {
    validatePayment(deployTieredTokenUriResolverKey);
    resolver = NFTRewardDataSourceFactory.createTieredTokenUriResolver(_baseUri, _idRange);
    emit Deployment('TieredTokenUriResolver', resolver);
  }

  function deployTieredPriceResolver(
    address _contributionToken,
    uint256 _mintCap,
    uint256 _userMintCap,
    RewardTier[] memory _tiers
  ) external payable returns (address resolver) {
    validatePayment(deployTieredPriceResolverKey);

    resolver = NFTRewardDataSourceFactory.createTieredPriceResolver(
      _contributionToken,
      _mintCap,
      _userMintCap,
      _tiers
    );

    emit Deployment('TieredPriceResolver', resolver);
  }

  function deployNFTRewardDataSource(
    uint256 _projectId,
    IJBDirectory _jbxDirectory,
    uint256 _maxSupply,
    JBTokenAmount memory _minContribution,
    string memory _name,
    string memory _symbol,
    string memory _uri,
    IToken721UriResolver _tokenUriResolverAddress,
    string memory _contractMetadataUri,
    address _admin,
    IPriceResolver _priceResolver
  ) external payable returns (address datasource) {
    validatePayment(deployNFTRewardDataSourceKey);

    datasource = NFTRewardDataSourceFactory.createNFTRewardDataSource(
      _projectId,
      _jbxDirectory,
      _maxSupply,
      _minContribution,
      _name,
      _symbol,
      _uri,
      _tokenUriResolverAddress,
      _contractMetadataUri,
      _admin,
      _priceResolver
    );

    emit Deployment('NFTRewardDataSourceDelegate', datasource);
  }
}
