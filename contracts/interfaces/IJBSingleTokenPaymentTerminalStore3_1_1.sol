// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBFundingCycle} from './../structs/JBFundingCycle.sol';
import {JBPayDelegateAllocation3_1_1} from './../structs/JBPayDelegateAllocation3_1_1.sol';
import {JBRedemptionDelegateAllocation3_1_1} from './../structs/JBRedemptionDelegateAllocation3_1_1.sol';
import {JBTokenAmount} from './../structs/JBTokenAmount.sol';
import {IJBDirectory} from './IJBDirectory.sol';
import {IJBFundingCycleStore} from './IJBFundingCycleStore.sol';
import {IJBPrices} from './IJBPrices.sol';
import {IJBPaymentTerminal} from './IJBPaymentTerminal.sol';

interface IJBSingleTokenPaymentTerminalStore3_1_1 {
  function fundingCycleStore() external view returns (IJBFundingCycleStore);

  function directory() external view returns (IJBDirectory);

  function prices() external view returns (IJBPrices);

  function balanceOf(
    IJBPaymentTerminal terminal,
    uint256 projectId,
    address token
  ) external view returns (uint256);

  function usedDistributionLimitOf(
    IJBPaymentTerminal terminal,
    uint256 projectId,
    address token,
    uint256 fundingCycleNumber,
    uint256 currency
  ) external view returns (uint256);

  function usedOverflowAllowanceOf(
    IJBPaymentTerminal terminal,
    uint256 projectId,
    address token,
    uint256 fundingCycleConfiguration,
    uint256 currency
  ) external view returns (uint256);

  function currentOverflowOf(
    IJBPaymentTerminal terminal,
    uint256 projectId,
    address[] calldata tokens,
    uint256 decimals,
    uint256 currency
  ) external view returns (uint256);

  function currentTotalOverflowOf(
    uint256 projectId,
    uint256 decimals,
    uint256 currency
  ) external view returns (uint256);

  function currentReclaimableOverflowOf(
    IJBPaymentTerminal terminal,
    uint256 projectId,
    address[] calldata tokens,
    uint256 _decimals,
    uint256 _currency,
    uint256 tokenCount,
    bool useTotalOverflow
  ) external view returns (uint256);

  function currentReclaimableOverflowOf(
    uint256 projectId,
    uint256 tokenCount,
    uint256 totalSupply,
    uint256 overflow
  ) external view returns (uint256);

  function recordPaymentFrom(
    address payer,
    JBTokenAmount memory amount,
    uint256 projectId,
    address beneficiary,
    bytes calldata metadata
  )
    external
    returns (
      JBFundingCycle memory fundingCycle,
      uint256 tokenCount,
      JBPayDelegateAllocation3_1_1[] memory delegateAllocations
    );

  function recordRedemptionFor(
    address holder,
    uint256 projectId,
    address[] memory _tokens,
    uint256 tokenCount,
    bytes calldata metadata
  )
    external
    returns (
      JBFundingCycle memory fundingCycle,
      uint256 reclaimAmount,
      JBRedemptionDelegateAllocation3_1_1[] memory delegateAllocations
    );

  function recordDistributionFor(
    uint256 projectId,
    address token,
    uint256 amount,
    uint256 currency
  ) external returns (JBFundingCycle memory fundingCycle, uint256 distributedAmount);

  function recordUsedAllowanceOf(
    uint256 projectId,
    address[] calldata tokens,
    uint256 amount,
    uint256 currency
  ) external returns (JBFundingCycle memory fundingCycle, uint256 withdrawnAmount);

  function recordAddedBalanceFor(uint256 projectId, address token, uint256 amount) external;

  function recordMigration(uint256 projectId, address token) external returns (uint256 balance);
}
