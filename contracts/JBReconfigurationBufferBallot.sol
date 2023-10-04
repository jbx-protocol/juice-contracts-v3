// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import {JBBallotState} from './enums/JBBallotState.sol';
import {IJBFundingCycleBallot} from './interfaces/IJBFundingCycleBallot.sol';
import {JBFundingCycle} from './structs/JBFundingCycle.sol';

/// @notice Manages approving funding cycle reconfigurations automatically after a buffer period.
contract JBReconfigurationBufferBallot is ERC165, IJBFundingCycleBallot {
  //*********************************************************************//
  // ---------------- public immutable stored properties --------------- //
  //*********************************************************************//

  /// @notice The number of seconds that must pass for a funding cycle reconfiguration to become either `Approved` or `Failed`.
  uint256 public immutable override duration;

  //*********************************************************************//
  // -------------------------- public views --------------------------- //
  //*********************************************************************//

  /// @notice The approval state of a particular funding cycle.
  /// @param _projectId The ID of the project to which the funding cycle being checked belongs.
  /// @param _configured The configuration of the funding cycle to check the state of.
  /// @param _start The start timestamp of the funding cycle to check the state of.
  /// @return The state of the provided ballot.
  function stateOf(
    uint256 _projectId,
    uint256 _configured,
    uint256 _start
  ) public view override returns (JBBallotState) {
    _projectId; // Prevents unused var compiler and natspec complaints.

    // If the provided configured timestamp is after the start timestamp, the ballot is Failed.
    if (_configured > _start) return JBBallotState.Failed;

    unchecked {
      // If there was sufficient time between configuration and the start of the cycle, it is approved. Otherwise, it is failed.
      // If the ballot hasn't yet started, it's state is ApprovalExpected.
      return
        (_start - _configured < duration)
          ? JBBallotState.Failed
          : (block.timestamp < _start - duration)
          ? JBBallotState.ApprovalExpected
          : JBBallotState.Approved;
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
      _interfaceId == type(IJBFundingCycleBallot).interfaceId ||
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
