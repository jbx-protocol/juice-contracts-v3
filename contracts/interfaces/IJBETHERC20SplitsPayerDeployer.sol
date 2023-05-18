// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './IJBSplitsPayer.sol';
import './IJBSplitsStore.sol';

interface IJBGasTokenERC20SplitsPayerDeployer {
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
    uint256 _defaultSplitsProjectId,
    uint256 _defaultSplitsDomain,
    uint256 _defaultSplitsGroup,
    uint256 _defaultProjectId,
    address payable _defaultBeneficiary,
    bool _defaultPreferClaimedTokens,
    string calldata _defaultMemo,
    bytes calldata _defaultMetadata,
    bool _preferAddToBalance,
    address _owner
  ) external returns (IJBSplitsPayer splitsPayer);

  function deploySplitsPayerWithSplits(
    uint256 _defaultSplitsProjectId,
    JBSplit[] memory _defaultSplits,
    IJBSplitsStore _splitsStore,
    uint256 _defaultProjectId,
    address payable _defaultBeneficiary,
    bool _defaultPreferClaimedTokens,
    string memory _defaultMemo,
    bytes memory _defaultMetadata,
    bool _defaultPreferAddToBalance,
    address _owner
  ) external returns (IJBSplitsPayer splitsPayer);
}
