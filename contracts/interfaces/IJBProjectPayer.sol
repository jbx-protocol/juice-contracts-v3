// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {IJBDirectory} from './IJBDirectory.sol';

interface IJBProjectPayer is IERC165 {
  event SetDefaultValues(
    uint256 indexed projectId,
    address indexed beneficiary,
    bool preferClaimedTokens,
    string memo,
    bytes metadata,
    bool preferAddToBalance,
    address caller
  );

  function directory() external view returns (IJBDirectory);

  function projectPayerDeployer() external view returns (address);

  function defaultProjectId() external view returns (uint256);

  function defaultBeneficiary() external view returns (address payable);

  function defaultPreferClaimedTokens() external view returns (bool);

  function defaultMemo() external view returns (string memory);

  function defaultMetadata() external view returns (bytes memory);

  function defaultPreferAddToBalance() external view returns (bool);

  function initialize(
    uint256 defaultProjectId,
    address payable defaultBeneficiary,
    bool defaultPreferClaimedTokens,
    string memory defaultMemo,
    bytes memory defaultMetadata,
    bool defaultPreferAddToBalance,
    address owner
  ) external;

  function setDefaultValues(
    uint256 projectId,
    address payable beneficiary,
    bool preferClaimedTokens,
    string memory memo,
    bytes memory metadata,
    bool defaultPreferAddToBalance
  ) external;

  function pay(
    uint256 projectId,
    address token,
    uint256 amount,
    uint256 decimals,
    address beneficiary,
    uint256 minReturnedTokens,
    bool preferClaimedTokens,
    string memory memo,
    bytes memory metadata
  ) external payable;

  function addToBalanceOf(
    uint256 projectId,
    address token,
    uint256 amount,
    uint256 decimals,
    string memory memo,
    bytes memory metadata
  ) external payable;

  receive() external payable;
}
