// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBFee} from './../structs/JBFee.sol';
import {JBDidRedeemData3_1_1} from './../structs/JBDidRedeemData3_1_1.sol';
import {JBDidPayData3_1_1} from './../structs/JBDidPayData3_1_1.sol';
import {IJBPayDelegate3_1_1} from './IJBPayDelegate3_1_1.sol';
import {IJBRedemptionDelegate3_1_1} from './IJBRedemptionDelegate3_1_1.sol';

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

  event DelegateDidRedeem(
    IJBRedemptionDelegate3_1_1 indexed delegate,
    JBDidRedeemData3_1_1 data,
    uint256 delegatedAmount,
    uint256 fee,
    address caller
  );

  event DelegateDidPay(
    IJBPayDelegate3_1_1 indexed delegate,
    JBDidPayData3_1_1 data,
    uint256 delegatedAmount,
    address caller
  );
}
