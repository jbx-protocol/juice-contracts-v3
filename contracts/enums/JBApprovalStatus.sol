// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice A ruleset's approval status in a ruleset approval hook.
enum JBApprovalStatus {
    Empty,
    UpcomingApprovable, // Standby,
    Active,
    ApprovalExpected,
    Approved,
    Failed
}
