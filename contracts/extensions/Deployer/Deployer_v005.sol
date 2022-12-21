// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../Auctions/DutchAuction.sol';
import '../Auctions/EnglishAuction.sol';
import '../NFT/NFUToken.sol';
import '../TokenLiquidator.sol';
import './Deployer_v004.sol';
import './Factories/PaymentProcessorFactory.sol';

/**
 * @notice This version of the deployer adds the ability to deploy PaymentProcessor instances to allow project to accept payments in various ERC20 tokens.
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Deployer_v005 is Deployer_v004 {
  bytes32 internal constant deployPaymentProcessorKey =
    keccak256(abi.encodePacked('deployPaymentProcessor'));
  ITokenLiquidator internal tokenLiquidator;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    DutchAuctionHouse _dutchAuctionSource,
    EnglishAuctionHouse _englishAuctionSource,
    NFUToken _nfuTokenSource,
    ITokenLiquidator _tokenLiquidator
  ) public virtual reinitializer(5) {
    __Ownable_init();
    __UUPSUpgradeable_init();

    dutchAuctionSource = _dutchAuctionSource;
    englishAuctionSource = _englishAuctionSource;
    nfuTokenSource = _nfuTokenSource;
    tokenLiquidator = _tokenLiquidator;

    prices[deployPaymentProcessorKey] = 1000000000000000; // 0.001 eth
  }

  function deployPaymentProcessor(
    IJBDirectory _jbxDirectory,
    IJBOperatorStore _jbxOperatorStore,
    IJBProjects _jbxProjects,
    uint256 _jbxProjectId,
    bool _ignoreFailures,
    bool _defaultLiquidation
  ) external payable returns (address processor) {
    validatePayment(deployPaymentProcessorKey);

    processor = PaymentProcessorFactory.createPaymentProcessor(
      _jbxDirectory,
      _jbxOperatorStore,
      _jbxProjects,
      tokenLiquidator,
      _jbxProjectId,
      _ignoreFailures,
      _defaultLiquidation
    );

    emit Deployment('PaymentProcessor', processor);
  }
}
