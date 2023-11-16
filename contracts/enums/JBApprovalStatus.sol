// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice A ruleset's approval status in a ruleset approval hook.
enum JBApprovalStatus {
  Empty,
  NextApprovable, // Standby
  Active,
  ApprovalExpected,
  Approved,
  Failed
}
