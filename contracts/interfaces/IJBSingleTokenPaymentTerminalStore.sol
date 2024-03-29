// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBFundingCycle} from './../structs/JBFundingCycle.sol';
import {JBPayDelegateAllocation} from './../structs/JBPayDelegateAllocation.sol';
import {JBRedemptionDelegateAllocation} from './../structs/JBRedemptionDelegateAllocation.sol';
import {JBTokenAmount} from './../structs/JBTokenAmount.sol';
import {IJBDirectory} from './IJBDirectory.sol';
import {IJBFundingCycleStore} from './IJBFundingCycleStore.sol';
import {IJBPrices} from './IJBPrices.sol';
import {IJBSingleTokenPaymentTerminal} from './IJBSingleTokenPaymentTerminal.sol';

interface IJBSingleTokenPaymentTerminalStore {
  function fundingCycleStore() external view returns (IJBFundingCycleStore);

  function directory() external view returns (IJBDirectory);

  function prices() external view returns (IJBPrices);

  function balanceOf(
    IJBSingleTokenPaymentTerminal terminal,
    uint256 projectId
  ) external view returns (uint256);

  function usedDistributionLimitOf(
    IJBSingleTokenPaymentTerminal terminal,
    uint256 projectId,
    uint256 fundingCycleNumber
  ) external view returns (uint256);

  function usedOverflowAllowanceOf(
    IJBSingleTokenPaymentTerminal terminal,
    uint256 projectId,
    uint256 fundingCycleConfiguration
  ) external view returns (uint256);

  function currentOverflowOf(
    IJBSingleTokenPaymentTerminal terminal,
    uint256 projectId
  ) external view returns (uint256);

  function currentTotalOverflowOf(
    uint256 projectId,
    uint256 decimals,
    uint256 currency
  ) external view returns (uint256);

  function currentReclaimableOverflowOf(
    IJBSingleTokenPaymentTerminal terminal,
    uint256 projectId,
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
    uint256 baseWeightCurrency,
    address beneficiary,
    string calldata inputMemo,
    bytes calldata metadata
  )
    external
    returns (
      JBFundingCycle memory fundingCycle,
      uint256 tokenCount,
      JBPayDelegateAllocation[] memory delegateAllocations,
      string memory outputMemo
    );

  function recordRedemptionFor(
    address holder,
    uint256 projectId,
    uint256 tokenCount,
    string calldata inputMemo,
    bytes calldata metadata
  )
    external
    returns (
      JBFundingCycle memory fundingCycle,
      uint256 reclaimAmount,
      JBRedemptionDelegateAllocation[] memory delegateAllocations,
      string memory outputMemo
    );

  function recordDistributionFor(
    uint256 projectId,
    uint256 amount,
    uint256 currency
  ) external returns (JBFundingCycle memory fundingCycle, uint256 distributedAmount);

  function recordUsedAllowanceOf(
    uint256 projectId,
    uint256 amount,
    uint256 currency
  ) external returns (JBFundingCycle memory fundingCycle, uint256 withdrawnAmount);

  function recordAddedBalanceFor(uint256 projectId, uint256 amount) external;

  function recordMigration(uint256 projectId) external returns (uint256 balance);
}
