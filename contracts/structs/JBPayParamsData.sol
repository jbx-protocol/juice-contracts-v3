// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBPaymentTerminal} from './../interfaces/IJBPaymentTerminal.sol';
import {JBTokenAmount} from './JBTokenAmount.sol';

/// @custom:member terminal The terminal that is facilitating the payment.
/// @custom:member payer The address from which the payment originated.
/// @custom:member amount The amount of the payment. Includes the token being paid, the value, the number of decimals included, and the currency of the amount.
/// @custom:member projectId The ID of the project being paid.
/// @custom:member currentFundingCycleConfiguration The configuration of the funding cycle during which the payment is being made.
/// @custom:member beneficiary The specified address that should be the beneficiary of anything that results from the payment.
/// @custom:member weight The weight of the funding cycle during which the payment is being made.
/// @custom:member reservedRate The reserved rate of the funding cycle during which the payment is being made.
/// @custom:member memo The memo that was sent alongside the payment.
/// @custom:member metadata Extra data provided by the payer.
struct JBPayParamsData {
  IJBPaymentTerminal terminal;
  address payer;
  JBTokenAmount amount;
  uint256 projectId;
  uint256 currentFundingCycleConfiguration;
  address beneficiary;
  uint256 weight;
  uint256 reservedRate;
  string memo;
  bytes metadata;
}
