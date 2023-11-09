// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBFee} from './../structs/JBFee.sol';
import {IJBAllowanceTerminal3_1} from './IJBAllowanceTerminal3_1.sol';
import {IJBDirectory} from './IJBDirectory.sol';
import {IJBPayDelegate3_1_1} from './IJBPayDelegate3_1_1.sol';
import {IJBPaymentTerminal} from './IJBPaymentTerminal.sol';
import {IJBPayoutTerminal3_1} from './IJBPayoutTerminal3_1.sol';
import {IJBPrices} from './IJBPrices.sol';
import {IJBProjects} from './IJBProjects.sol';
import {IJBRedemptionDelegate3_1_1} from './IJBRedemptionDelegate3_1_1.sol';
import {IJBRedemptionTerminal} from './IJBRedemptionTerminal.sol';
import {IJBSplitsStore} from './IJBSplitsStore.sol';
import {IJBTerminalStore} from './IJBTerminalStore.sol';
import {JBDidPayData3_1_1} from './../structs/JBDidPayData3_1_1.sol';
import {JBDidRedeemData3_1_1} from './../structs/JBDidRedeemData3_1_1.sol';
import {JBSplit} from './../structs/JBSplit.sol';

interface IJBPayoutRedemptionTerminal is
  IJBPaymentTerminal,
  IJBPayoutTerminal3_1,
  IJBAllowanceTerminal3_1,
  IJBRedemptionTerminal
{
  event AddToBalance(
    uint256 indexed projectId,
    uint256 amount,
    uint256 refundedFees,
    bytes metadata,
    address caller
  );

  event Migrate(
    uint256 indexed projectId,
    IJBPaymentTerminal indexed to,
    uint256 amount,
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
    address caller
  );

  event UseAllowance(
    uint256 indexed fundingCycleConfiguration,
    uint256 indexed fundingCycleNumber,
    uint256 indexed projectId,
    address beneficiary,
    uint256 amount,
    uint256 distributedAmount,
    uint256 netDistributedamount,
    string memo,
    address caller
  );

  event HoldFee(
    uint256 indexed projectId,
    uint256 indexed amount,
    uint256 indexed fee,
    address beneficiary,
    address caller
  );

  event ProcessFee(
    uint256 indexed projectId,
    uint256 indexed amount,
    bool indexed wasHeld,
    address beneficiary,
    address caller
  );

  event RefundHeldFees(
    uint256 indexed projectId,
    uint256 indexed amount,
    uint256 indexed refundedFees,
    uint256 leftoverAmount,
    address caller
  );

  event Pay(
    uint256 indexed fundingCycleConfiguration,
    uint256 indexed fundingCycleNumber,
    uint256 indexed projectId,
    address payer,
    address beneficiary,
    uint256 amount,
    uint256 beneficiaryTokenCount,
    bytes metadata,
    address caller
  );

  event RedeemTokens(
    uint256 indexed fundingCycleConfiguration,
    uint256 indexed fundingCycleNumber,
    uint256 indexed projectId,
    address holder,
    address beneficiary,
    uint256 tokenCount,
    uint256 reclaimedAmount,
    bytes metadata,
    address caller
  );

  event DistributeToPayoutSplit(
    uint256 indexed projectId,
    uint256 indexed domain,
    uint256 indexed group,
    JBSplit split,
    uint256 amount,
    uint256 netAmount,
    address caller
  );

  event SetFee(uint256 fee, address caller);

  event SetFeelessAddress(address indexed addrs, bool indexed flag, address caller);

  event PayoutReverted(
    uint256 indexed projectId,
    JBSplit split,
    uint256 amount,
    bytes reason,
    address caller
  );

  event FeeReverted(
    uint256 indexed projectId,
    uint256 indexed feeProjectId,
    uint256 amount,
    bytes reason,
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

  function PROJECTS() external view returns (IJBProjects);

  function SPLITS() external view returns (IJBSplitsStore);

  function DIRECTORY() external view returns (IJBDirectory);

  function STORE() external view returns (IJBTerminalStore);

  function heldFeesOf(uint256 projectId) external view returns (JBFee[] memory);

  function fee() external view returns (uint256);

  function isFeelessAddress(address account) external view returns (bool);

  function migrate(
    uint256 projectId,
    address token,
    IJBPaymentTerminal to
  ) external returns (uint256 balance);

  function processFees(uint256 projectId, address token) external;

  function setFee(uint256 fee) external;

  function setFeelessAddress(address account, bool flag) external;
}
