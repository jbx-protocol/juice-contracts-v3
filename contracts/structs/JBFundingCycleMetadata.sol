// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @custom:member global Data used globally in non-migratable ecosystem contracts.
/// @custom:member reservedRate The reserved rate of the funding cycle. This number is a percentage calculated out of `JBConstants.MAX_RESERVED_RATE`.
/// @custom:member redemptionRate The redemption rate of the funding cycle. This number is a percentage calculated out of `JBConstants.MAX_REDEMPTION_RATE`.
/// @custom:member baseCurrency The currency on which to base the funding cycle's weight.
/// @custom:member pausePay A flag indicating if the pay functionality should be paused during the funding cycle.
/// @custom:member pauseTokenCreditTransfers A flag indicating if the project token transfer functionality should be paused during the funding cycle.
/// @custom:member allowMinting A flag indicating if minting tokens should be allowed during this funding cycle.
/// @custom:member allowTerminalMigration A flag indicating if migrating terminals should be allowed during this funding cycle.
/// @custom:member allowSetTerminals A flag indicating if a project's terminals can be added or removed.
/// @custom:member allowControllerMigration A flag indicating if migrating controllers should be allowed during this funding cycle.
/// @custom:member allowSetController A flag indicating if a project's controller can be changed.
/// @custom:member holdFees A flag indicating if fees should be held during this funding cycle.
/// @custom:member useTotalOverflowForRedemptions A flag indicating if redemptions should use the project's balance held in all terminals instead of the project's local terminal balance from which the redemption is being fulfilled.
/// @custom:member useDataSourceForPay A flag indicating if the data source should be used for pay transactions during this funding cycle.
/// @custom:member useDataSourceForRedeem A flag indicating if the data source should be used for redeem transactions during this funding cycle.
/// @custom:member dataSource The data source to use during this funding cycle.
/// @custom:member metadata Metadata of the metadata, up to uint8 in size.
struct JBFundingCycleMetadata {
    uint256 reservedRate;
    uint256 redemptionRate;
    uint256 baseCurrency;
    bool pausePay;
    bool pauseTokenCreditTransfers;
    bool allowMinting;
    bool allowTerminalMigration;
    bool allowSetTerminals;
    bool allowControllerMigration;
    bool allowSetController;
    bool holdFees;
    bool useTotalOverflowForRedemptions;
    bool useDataSourceForPay;
    bool useDataSourceForRedeem;
    address dataSource;
    uint256 metadata;
}
