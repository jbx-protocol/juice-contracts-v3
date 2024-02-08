// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBDirectory} from './IJBDirectory.sol';
import {IJBPaymentTerminal} from './IJBPaymentTerminal.sol';
import {IJBPayoutTerminal3_1} from './IJBPayoutTerminal3_1.sol';
import {IJBProjects} from './IJBProjects.sol';

interface IJBPayoutRedemptionPaymentTerminal3_1_1_e is
  IJBPaymentTerminal,
  IJBPayoutTerminal3_1
{
  event AddToBalance(
    uint256 indexed projectId,
    uint256 amount,
    uint256 refundedFees,
    string memo,
    bytes metadata,
    address caller
  );

  event DistributePayouts(
    uint256 indexed fundingCycleConfiguration,
    uint256 indexed fundingCycleNumber,
    uint256 indexed projectId,
    address beneficiary,
    uint256 amount,
    uint256 distributedAmount,
    uint256 fee,
    uint256 beneficiaryDistributionAmount,
    bytes metadata,
    address caller
  );

  event ProcessFee(
    uint256 indexed projectId,
    uint256 indexed amount,
    bool indexed wasHeld,
    address beneficiary,
    address caller
  );

  event FeeReverted(
    uint256 indexed projectId,
    uint256 indexed feeProjectId,
    uint256 amount,
    bytes reason,
    address caller
  );

  function projects() external view returns (IJBProjects);

  function directory() external view returns (IJBDirectory);

  function fee() external view returns (uint256);
}

