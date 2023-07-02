// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {JBSplit} from './../structs/JBSplit.sol';
import {JBGroupedSplits} from './../structs/JBGroupedSplits.sol';
import {IJBSplitsStore} from './IJBSplitsStore.sol';

interface IJBSplitsPayer is IERC165 {
  event SetDefaultSplitsReference(
    uint256 indexed projectId,
    uint256 indexed domain,
    uint256 indexed group,
    address caller
  );
  event Pay(
    uint256 indexed projectId,
    address beneficiary,
    address token,
    uint256 amount,
    uint256 decimals,
    uint256 leftoverAmount,
    uint256 minReturnedTokens,
    bool preferClaimedTokens,
    string memo,
    bytes metadata,
    address caller
  );

  event AddToBalance(
    uint256 indexed projectId,
    address beneficiary,
    address token,
    uint256 amount,
    uint256 decimals,
    uint256 leftoverAmount,
    string memo,
    bytes metadata,
    address caller
  );

  event DistributeToSplitGroup(
    uint256 indexed projectId,
    uint256 indexed domain,
    uint256 indexed group,
    address caller
  );

  event DistributeToSplit(
    JBSplit split,
    uint256 amount,
    address defaultBeneficiary,
    address caller
  );

  function defaultSplitsProjectId() external view returns (uint256);

  function defaultSplitsDomain() external view returns (uint256);

  function defaultSplitsGroup() external view returns (uint256);

  function splitsStore() external view returns (IJBSplitsStore);

  function initialize(
    uint256 defaultSplitsProjectId,
    uint256 defaultSplitsDomain,
    uint256 defaultSplitsGroup,
    uint256 defaultProjectId,
    address payable defaultBeneficiary,
    bool defaultPreferClaimedTokens,
    string memory defaultMemo,
    bytes memory defaultMetadata,
    bool preferAddToBalance,
    address owner
  ) external;

  function setDefaultSplitsReference(uint256 projectId, uint256 domain, uint256 group) external;

  function setDefaultSplits(
    uint256 projectId,
    uint256 domain,
    uint256 group,
    JBGroupedSplits[] memory splitsGroup
  ) external;
}
