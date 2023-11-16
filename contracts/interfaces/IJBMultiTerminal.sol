// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPermit2} from '@permit2/src/src/interfaces/IPermit2.sol';
import {JBFee} from './../structs/JBFee.sol';
import {JBAccountingContext} from './../structs/JBAccountingContext.sol';
import {IJBDirectory} from './IJBDirectory.sol';
import {IJBPayDelegate} from './IJBPayDelegate.sol';
import {IJBPaymentTerminal} from './IJBPaymentTerminal.sol';
import {IJBPrices} from './IJBPrices.sol';
import {IJBProjects} from './IJBProjects.sol';
import {IJBRedeemDelegate} from './IJBRedeemDelegate.sol';
import {IJBSplitsStore} from './IJBSplitsStore.sol';
import {IJBTerminalStore} from './IJBTerminalStore.sol';
import {JBDidPayData} from './../structs/JBDidPayData.sol';
import {JBDidRedeemData} from './../structs/JBDidRedeemData.sol';
import {JBSplit} from './../structs/JBSplit.sol';

interface IJBMultiTerminal is IJBPaymentTerminal {
  event AddToBalance(
    uint256 indexed projectId,
    uint256 amount,
    uint256 refundedFees,
    string memo,
    bytes metadata,
    address caller
  );

  event Migrate(
    uint256 indexed projectId,
    address indexed token,
    IJBPaymentTerminal indexed to,
    uint256 amount,
    address caller
  );

  event DistributePayouts(
    uint256 indexed rulesetId,
    uint256 indexed rulesetNumber,
    uint256 indexed projectId,
    address beneficiary,
    uint256 amount,
    uint256 distributedAmount,
    uint256 fee,
    uint256 beneficiaryDistributionAmount,
    address caller
  );

  event UseAllowance(
    uint256 indexed rulesetId,
    uint256 indexed rulesetNumber,
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
    uint256 indexed rulesetId,
    uint256 indexed rulesetNumber,
    uint256 indexed projectId,
    address payer,
    address beneficiary,
    uint256 amount,
    uint256 beneficiaryTokenCount,
    string memo,
    bytes metadata,
    address caller
  );

  event RedeemTokens(
    uint256 indexed rulesetId,
    uint256 indexed rulesetNumber,
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

  event SetFeelessAddress(address indexed addrs, bool indexed flag, address caller);

  event SetAccountingContext(
    uint256 indexed projectId,
    address indexed token,
    JBAccountingContext context,
    address caller
  );

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
    IJBRedeemDelegate indexed delegate,
    JBDidRedeemData data,
    uint256 delegatedAmount,
    uint256 fee,
    address caller
  );

  event DelegateDidPay(
    IJBPayDelegate indexed delegate,
    JBDidPayData data,
    uint256 delegatedAmount,
    address caller
  );

  function PROJECTS() external view returns (IJBProjects);

  function SPLITS() external view returns (IJBSplitsStore);

  function DIRECTORY() external view returns (IJBDirectory);

  function STORE() external view returns (IJBTerminalStore);

  function PERMIT2() external returns (IPermit2);

  function FEE() external view returns (uint256);

  function heldFeesOf(uint256 projectId) external view returns (JBFee[] memory);

  function isFeelessAddress(address account) external view returns (bool);

  function processFees(uint256 projectId, address token) external;

  function setFeelessAddress(address account, bool flag) external;
}
