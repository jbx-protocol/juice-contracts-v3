// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './../structs/JBFee.sol';
import './IJBAllowanceTerminal3_1.sol';
import './IJBDirectory.sol';
import './IJBFeeGauge.sol';
import './IJBFeeHoldingTerminal.sol';
import './IJBPayDelegate.sol';
import './IJBPaymentTerminal.sol';
import './IJBPayoutTerminal3_1.sol';
import './IJBPrices.sol';
import './IJBProjects.sol';
import './IJBRedemptionDelegate.sol';
import './IJBRedemptionTerminal.sol';
import './IJBSingleTokenPaymentTerminalStore.sol';
import './IJBSplitsStore.sol';

interface IJBPayoutRedemptionPaymentTerminal3_1_1 {
  event RedeemTokens(
    uint256 indexed fundingCycleConfiguration,
    uint256 indexed fundingCycleNumber,
    uint256 indexed projectId,
    address holder,
    address beneficiary,
    uint256 tokenCount,
    uint256 reclaimedAmount,
    uint256 fee,
    string memo,
    bytes metadata,
    address caller
  );
}
