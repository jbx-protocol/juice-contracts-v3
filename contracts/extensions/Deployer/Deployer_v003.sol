// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Deployer_v002.sol';
import './AuctionsFactory.sol';

/**
 * @notice
 */
/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract Deployer_v003 is Deployer_v002 {
  function deployDutchAuction(
    address _source,
    uint256 _projectId,
    IJBPaymentTerminal _feeReceiver,
    uint256 _feeRate,
    bool _allowPublicAuctions,
    uint256 _periodDuration,
    address _owner,
    IJBDirectory _directory
  ) external returns (address) {
    address s = AuctionsFactory.createDutchAuction(
      _source,
      _projectId,
      _feeReceiver,
      _feeRate,
      _allowPublicAuctions,
      _periodDuration,
      _owner,
      _directory
    );

    emit Deployment('DutchAuctionHouse', s);

    return s;
  }

  function deployEnglishAuction(
    address _source,
    uint256 _projectId,
    IJBPaymentTerminal _feeReceiver,
    uint256 _feeRate,
    bool _allowPublicAuctions,
    address _owner,
    IJBDirectory _directory
  ) external returns (address) {
    address s = AuctionsFactory.createEnglishAuction(
      _source,
      _projectId,
      _feeReceiver,
      _feeRate,
      _allowPublicAuctions,
      _owner,
      _directory
    );

    emit Deployment('EnglishAuctionHouse', s);

    return s;
  }
}
