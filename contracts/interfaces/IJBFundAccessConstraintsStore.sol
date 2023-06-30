// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {JBFundAccessConstraints} from './../structs/JBFundAccessConstraints.sol';
import {IJBPaymentTerminal} from './IJBPaymentTerminal.sol';

interface IJBFundAccessConstraintsStore is IERC165 {
  event SetFundAccessConstraints(
    uint256 indexed fundingCycleConfiguration,
    uint256 indexed projectId,
    JBFundAccessConstraints constraints,
    address caller
  );

  function distributionLimitOf(
    uint256 projectId,
    uint256 configuration,
    IJBPaymentTerminal terminal,
    address token
  ) external view returns (uint256 distributionLimit, uint256 distributionLimitCurrency);

  function overflowAllowanceOf(
    uint256 projectId,
    uint256 configuration,
    IJBPaymentTerminal terminal,
    address token
  ) external view returns (uint256 overflowAllowance, uint256 overflowAllowanceCurrency);

  function setFor(
    uint256 projectId,
    uint256 configuration,
    JBFundAccessConstraints[] memory fundAccessConstaints
  ) external;
}
