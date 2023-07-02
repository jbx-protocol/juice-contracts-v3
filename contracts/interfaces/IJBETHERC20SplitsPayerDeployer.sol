// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBSplitsPayer} from './IJBSplitsPayer.sol';
import {IJBSplitsStore} from './IJBSplitsStore.sol';
import {JBSplit} from './../structs/JBSplit.sol';

interface IJBETHERC20SplitsPayerDeployer {
  event DeploySplitsPayer(
    IJBSplitsPayer indexed splitsPayer,
    uint256 defaultSplitsProjectId,
    uint256 defaultSplitsDomain,
    uint256 defaultSplitsGroup,
    IJBSplitsStore splitsStore,
    uint256 defaultProjectId,
    address defaultBeneficiary,
    bool defaultPreferClaimedTokens,
    string defaultMemo,
    bytes defaultMetadata,
    bool preferAddToBalance,
    address owner,
    address caller
  );

  function deploySplitsPayer(
    uint256 defaultSplitsProjectId,
    uint256 defaultSplitsDomain,
    uint256 defaultSplitsGroup,
    uint256 defaultProjectId,
    address payable defaultBeneficiary,
    bool defaultPreferClaimedTokens,
    string calldata defaultMemo,
    bytes calldata defaultMetadata,
    bool preferAddToBalance,
    address owner
  ) external returns (IJBSplitsPayer splitsPayer);

  function deploySplitsPayerWithSplits(
    uint256 defaultSplitsProjectId,
    JBSplit[] memory defaultSplits,
    IJBSplitsStore splitsStore,
    uint256 defaultProjectId,
    address payable defaultBeneficiary,
    bool defaultPreferClaimedTokens,
    string memory defaultMemo,
    bytes memory defaultMetadata,
    bool defaultPreferAddToBalance,
    address owner
  ) external returns (IJBSplitsPayer splitsPayer);
}
