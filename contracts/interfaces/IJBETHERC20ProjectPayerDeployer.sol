// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBDirectory} from './IJBDirectory.sol';
import {IJBProjectPayer} from './IJBProjectPayer.sol';

interface IJBETHERC20ProjectPayerDeployer {
  event DeployProjectPayer(
    IJBProjectPayer indexed projectPayer,
    uint256 defaultProjectId,
    address defaultBeneficiary,
    bool defaultPreferClaimedTokens,
    string defaultMemo,
    bytes defaultMetadata,
    bool preferAddToBalance,
    IJBDirectory directory,
    address owner,
    address caller
  );

  function deployProjectPayer(
    uint256 defaultProjectId,
    address payable defaultBeneficiary,
    bool defaultPreferClaimedTokens,
    string memory defaultMemo,
    bytes memory defaultMetadata,
    bool preferAddToBalance,
    address owner
  ) external returns (IJBProjectPayer projectPayer);
}
