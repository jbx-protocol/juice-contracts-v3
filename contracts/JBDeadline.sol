// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {JBApprovalStatus} from './enums/JBApprovalStatus.sol';
import {IJBRulesetApprovalHook} from './interfaces/IJBRulesetApprovalHook.sol';
import {JBRuleset} from './structs/JBRuleset.sol';

/// @notice Ruleset approval hook which rejects rulesets if they are not queued `duration` seconds before the current ruleset ends.
contract JBDeadline is ERC165, IJBRulesetApprovalHook {
  //*********************************************************************//
  // ---------------- public immutable stored properties --------------- //
  //*********************************************************************//

  /// @notice The number of seconds that must pass for a ruleset reconfiguration to become either `Approved` or `Failed`.
  uint256 public immutable override duration;

  //*********************************************************************//
  // -------------------------- public views --------------------------- //
  //*********************************************************************//

  /// @notice The approval status of a particular ruleset.
  /// @param _projectId The ID of the project to which the ruleset being checked belongs.
  /// @param _configured The configuration of the ruleset to check the status of.
  /// @param _start The start timestamp of the ruleset to check the status of.
  /// @return The status of the provided approval hook.
  function approvalStatusOf(
    uint256 _projectId,
    uint256 _configured,
    uint256 _start
  ) public view override returns (JBApprovalStatus) {
    _projectId; // Prevents unused var compiler and natspec complaints.

    // If the provided configured timestamp is after the start timestamp, the approval hook is Failed.
    if (_configured > _start) return JBApprovalStatus.Failed;

    unchecked {
      // If there was sufficient time between configuration and the start of the cycle, it is approved. Otherwise, it is failed.
      // If the approval hook hasn't yet started, its approval status is ApprovalExpected.
      return
        (_start - _configured < duration)
          ? JBApprovalStatus.Failed
          : (block.timestamp < _start - duration)
          ? JBApprovalStatus.ApprovalExpected
          : JBApprovalStatus.Approved;
    }
  }

  /// @notice Indicates if this contract adheres to the specified interface.
  /// @dev See {IERC165-supportsInterface}.
  /// @param _interfaceId The ID of the interface to check for adherance to.
  /// @return A flag indicating if this contract adheres to the specified interface.
  function supportsInterface(
    bytes4 _interfaceId
  ) public view virtual override(ERC165, IERC165) returns (bool) {
    return
      _interfaceId == type(IJBRulesetApprovalHook).interfaceId ||
      super.supportsInterface(_interfaceId);
  }

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  /// @param _duration The number of seconds to wait until a reconfiguration can be either `Approved` or `Failed`.
  constructor(uint256 _duration) {
    duration = _duration;
  }
}
