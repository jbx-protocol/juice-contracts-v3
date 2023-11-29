// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {JBFundingCycle} from "./../structs/JBFundingCycle.sol";
import {JBFundingCycleMetadata} from "./../structs/JBFundingCycleMetadata.sol";
import {JBGlobalFundingCycleMetadata} from "./../structs/JBGlobalFundingCycleMetadata.sol";
import {JBConstants} from "./JBConstants.sol";

library JBFundingCycleMetadataResolver {
    function global(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (JBGlobalFundingCycleMetadata memory)
    {
        return JBGlobalFundingCycleMetadata(
            ((_fundingCycle.metadata >> 4) & 1) == 1, ((_fundingCycle.metadata >> 5) & 1) == 1
        );
    }

    function reservedRate(JBFundingCycle memory _fundingCycle) internal pure returns (uint256) {
        return uint256(uint16(_fundingCycle.metadata >> 6));
    }

    function redemptionRate(JBFundingCycle memory _fundingCycle) internal pure returns (uint256) {
        // Redemption rate is a number 0-10000.
        return uint256(uint16(_fundingCycle.metadata >> 22));
    }

    function baseCurrency(JBFundingCycle memory _fundingCycle) internal pure returns (uint256) {
        // Currency is a number 0-4294967296.
        return uint256(uint32(_fundingCycle.metadata >> 38));
    }

    function payPaused(JBFundingCycle memory _fundingCycle) internal pure returns (bool) {
        return ((_fundingCycle.metadata >> 70) & 1) == 1;
    }

    function tokenCreditTransfersPaused(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return ((_fundingCycle.metadata >> 71) & 1) == 1;
    }

    function mintingAllowed(JBFundingCycle memory _fundingCycle) internal pure returns (bool) {
        return ((_fundingCycle.metadata >> 72) & 1) == 1;
    }

    function terminalMigrationAllowed(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return ((_fundingCycle.metadata >> 73) & 1) == 1;
    }

    function controllerMigrationAllowed(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return ((_fundingCycle.metadata >> 74) & 1) == 1;
    }

    function shouldHoldFees(JBFundingCycle memory _fundingCycle) internal pure returns (bool) {
        return ((_fundingCycle.metadata >> 75) & 1) == 1;
    }

    function useTotalOverflowForRedemptions(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return ((_fundingCycle.metadata >> 76) & 1) == 1;
    }

    function useDataSourceForPay(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return (_fundingCycle.metadata >> 77) & 1 == 1;
    }

    function useDataSourceForRedeem(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return (_fundingCycle.metadata >> 78) & 1 == 1;
    }

    function dataSource(JBFundingCycle memory _fundingCycle) internal pure returns (address) {
        return address(uint160(_fundingCycle.metadata >> 79));
    }

    function metadata(JBFundingCycle memory _fundingCycle) internal pure returns (uint256) {
        return uint256(uint8(_fundingCycle.metadata >> 239));
    }

    /// @notice Pack the funding cycle metadata.
    /// @param _metadata The metadata to validate and pack.
    /// @return packed The packed uint256 of all metadata params. The first 8 bits specify the version.
    function packFundingCycleMetadata(JBFundingCycleMetadata memory _metadata)
        internal
        pure
        returns (uint256 packed)
    {
        // version 1 in the bits 0-3 (4 bits).
        packed = 1;
        // allow set terminals in bit 4.
        if (_metadata.global.allowSetTerminals) packed |= 1 << 4;
        // allow set controller in bit 5.
        if (_metadata.global.allowSetController) packed |= 1 << 5;
        // reserved rate in bits 6-21 (16 bits).
        packed |= _metadata.reservedRate << 6;
        // redemption rate in bits 22-37 (16 bits).
        // redemption rate is a number 0-10000.
        packed |= _metadata.redemptionRate << 22;
        // base currency in bits 38-69 (32 bits).
        // base currency is a number 0-16777215.
        packed |= _metadata.baseCurrency << 38;
        // pause pay in bit 70.
        if (_metadata.pausePay) packed |= 1 << 70;
        // pause transfers in bit 71.
        if (_metadata.pauseTokenCreditTransfers) packed |= 1 << 71;
        // allow minting in bit 72.
        if (_metadata.allowMinting) packed |= 1 << 72;
        // allow terminal migration in bit 73.
        if (_metadata.allowTerminalMigration) packed |= 1 << 73;
        // allow controller migration in bit 74.
        if (_metadata.allowControllerMigration) packed |= 1 << 74;
        // hold fees in bit 75.
        if (_metadata.holdFees) packed |= 1 << 75;
        // useTotalOverflowForRedemptions in bit 76.
        if (_metadata.useTotalOverflowForRedemptions) packed |= 1 << 76;
        // use pay data source in bit 77.
        if (_metadata.useDataSourceForPay) packed |= 1 << 77;
        // use redeem data source in bit 78.
        if (_metadata.useDataSourceForRedeem) packed |= 1 << 78;
        // data source address in bits 79-238.
        packed |= uint256(uint160(address(_metadata.dataSource))) << 79;
        // metadata in bits 239-254 (16 bits).
        packed |= _metadata.metadata << 239;
    }

    /// @notice Expand the funding cycle metadata.
    /// @param _fundingCycle The funding cycle having its metadata expanded.
    /// @return metadata The metadata object.
    function expandMetadata(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (JBFundingCycleMetadata memory)
    {
        return JBFundingCycleMetadata(
            global(_fundingCycle),
            reservedRate(_fundingCycle),
            redemptionRate(_fundingCycle),
            baseCurrency(_fundingCycle),
            payPaused(_fundingCycle),
            tokenCreditTransfersPaused(_fundingCycle),
            mintingAllowed(_fundingCycle),
            terminalMigrationAllowed(_fundingCycle),
            controllerMigrationAllowed(_fundingCycle),
            shouldHoldFees(_fundingCycle),
            useTotalOverflowForRedemptions(_fundingCycle),
            useDataSourceForPay(_fundingCycle),
            useDataSourceForRedeem(_fundingCycle),
            dataSource(_fundingCycle),
            metadata(_fundingCycle)
        );
    }
}
