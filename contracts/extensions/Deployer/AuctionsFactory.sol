// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/proxy/Clones.sol';

import '../../interfaces/IJBDirectory.sol';
import '../../interfaces/IJBPaymentTerminal.sol';

import '../Auctions/DutchAuction.sol';
import '../Auctions/EnglishAuction.sol';

library AuctionsFactory {
  function createDutchAuction(
    address _source, // DutchAuctionHouse
    uint256 _projectId,
    IJBPaymentTerminal _feeReceiver,
    uint256 _feeRate,
    bool _allowPublicAuctions,
    uint256 _periodDuration,
    address _owner,
    IJBDirectory _directory
  ) public returns (address) {
    // TODO: supportsInterface check on _source
    address auctionClone = Clones.clone(_source);
    DutchAuctionHouse(auctionClone).initialize(
      _projectId,
      _feeReceiver,
      _feeRate,
      _allowPublicAuctions,
      _periodDuration,
      _owner,
      _directory
    );

    return address(auctionClone);
  }

  function createEnglishAuction(
    address _source, // EnglishAuctionHouse
    uint256 _projectId,
    IJBPaymentTerminal _feeReceiver,
    uint256 _feeRate,
    bool _allowPublicAuctions,
    address _owner,
    IJBDirectory _directory
  ) public returns (address) {
    address auctionClone = Clones.clone(_source);
    EnglishAuctionHouse(auctionClone).initialize(
      _projectId,
      _feeReceiver,
      _feeRate,
      _allowPublicAuctions,
      _owner,
      _directory
    );

    return address(auctionClone);
  }
}
