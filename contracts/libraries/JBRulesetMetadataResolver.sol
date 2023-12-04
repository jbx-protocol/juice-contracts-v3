// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {JBFundingCycle} from "./../structs/JBFundingCycle.sol";
import {JBRulesetMetadata} from "./../structs/JBRulesetMetadata.sol";
import {JBConstants} from "./JBConstants.sol";

library JBFundingCycleMetadataResolver {
    function reservedRate(JBFundingCycle memory _fundingCycle) internal pure returns (uint256) {
        return uint256(uint16(_fundingCycle.metadata >> 4));
    }

    function redemptionRate(JBFundingCycle memory _fundingCycle) internal pure returns (uint256) {
        // Redemption rate is a number 0-10000.
        return uint256(uint16(_fundingCycle.metadata >> 20));
    }

    function baseCurrency(JBFundingCycle memory _fundingCycle) internal pure returns (uint256) {
        // Currency is a number 0-4294967296.
        return uint256(uint32(_fundingCycle.metadata >> 36));
    }

    function payPaused(JBFundingCycle memory _fundingCycle) internal pure returns (bool) {
        return ((_fundingCycle.metadata >> 68) & 1) == 1;
    }

    function tokenCreditTransfersPaused(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return ((_fundingCycle.metadata >> 69) & 1) == 1;
    }

    function mintingAllowed(JBFundingCycle memory _fundingCycle) internal pure returns (bool) {
        return ((_fundingCycle.metadata >> 70) & 1) == 1;
    }

    function terminalMigrationAllowed(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return ((_fundingCycle.metadata >> 71) & 1) == 1;
    }

    function setTerminalsAllowed(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return ((_fundingCycle.metadata >> 72) & 1) == 1;
    }

    function controllerMigrationAllowed(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return ((_fundingCycle.metadata >> 73) & 1) == 1;
    }

    function setControllerAllowed(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return ((_fundingCycle.metadata >> 74) & 1) == 1;
    }

    function shouldHoldFees(JBFundingCycle memory _fundingCycle) internal pure returns (bool) {
        return ((_fundingCycle.metadata >> 75) & 1) == 1;
    }

    function useTotalSurplusForRedemptions(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return ((_fundingCycle.metadata >> 76) & 1) == 1;
    }

    function useDataHookForPay(JBFundingCycle memory _fundingCycle) internal pure returns (bool) {
        return (_fundingCycle.metadata >> 77) & 1 == 1;
    }

    function useDataHookForRedeem(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (bool)
    {
        return (_fundingCycle.metadata >> 78) & 1 == 1;
    }

    function dataHook(JBFundingCycle memory _fundingCycle) internal pure returns (address) {
        return address(uint160(_fundingCycle.metadata >> 79));
    }

    function metadata(JBFundingCycle memory _fundingCycle) internal pure returns (uint256) {
        return uint256(uint16(_fundingCycle.metadata >> 239));
    }

    /// @notice Pack the funding cycle metadata.
    /// @param _metadata The metadata to validate and pack.
    /// @return packed The packed uint256 of all metadata params. The first 8 bits specify the version.
    function packFundingCycleMetadata(JBRulesetMetadata memory _metadata)
        internal
        pure
        returns (uint256 packed)
    {
        // version 1 in the bits 0-3 (4 bits).
        packed = 1;
        // reserved rate in bits 4-19 (16 bits).
        packed |= _metadata.reservedRate << 4;
        // redemption rate in bits 20-35 (16 bits).
        // redemption rate is a number 0-10000.
        packed |= _metadata.redemptionRate << 20;
        // base currency in bits 36-67 (32 bits).
        // base currency is a number 0-16777215.
        packed |= _metadata.baseCurrency << 36;
        // pause pay in bit 68.
        if (_metadata.pausePay) packed |= 1 << 68;
        // pause transfers in bit 69.
        if (_metadata.pauseCreditTransfers) packed |= 1 << 69;
        // allow minting in bit 70.
        if (_metadata.allowMinting) packed |= 1 << 70;
        // allow terminal migration in bit 71.
        if (_metadata.allowTerminalMigration) packed |= 1 << 71;
        // allow set terminals in bit 72.
        if (_metadata.allowSetTerminals) packed |= 1 << 72;
        // allow controller migration in bit 73.
        if (_metadata.allowControllerMigration) packed |= 1 << 73;
        // allow set controller in bit 74.
        if (_metadata.allowSetController) packed |= 1 << 74;
        // hold fees in bit 75.
        if (_metadata.holdFees) packed |= 1 << 75;
        // useTotalSurplusForRedemptions in bit 76.
        if (_metadata.useTotalSurplusForRedemptions) packed |= 1 << 76;
        // use pay data source in bit 77.
        if (_metadata.useDataHookForPay) packed |= 1 << 77;
        // use redeem data source in bit 78.
        if (_metadata.useDataHookForRedeem) packed |= 1 << 78;
        // data source address in bits 79-238.
        packed |= uint256(uint160(address(_metadata.dataHook))) << 79;
        // metadata in bits 239-254 (16 bits).
        packed |= _metadata.metadata << 239;
    }

    /// @notice Expand the funding cycle metadata.
    /// @param _fundingCycle The funding cycle having its metadata expanded.
    /// @return metadata The metadata object.
    function expandMetadata(JBFundingCycle memory _fundingCycle)
        internal
        pure
        returns (JBRulesetMetadata memory)
    {
        return JBRulesetMetadata(
            reservedRate(_fundingCycle),
            redemptionRate(_fundingCycle),
            baseCurrency(_fundingCycle),
            payPaused(_fundingCycle),
            tokenCreditTransfersPaused(_fundingCycle),
            mintingAllowed(_fundingCycle),
            terminalMigrationAllowed(_fundingCycle),
            setTerminalsAllowed(_fundingCycle),
            controllerMigrationAllowed(_fundingCycle),
            setControllerAllowed(_fundingCycle),
            shouldHoldFees(_fundingCycle),
            useTotalSurplusForRedemptions(_fundingCycle),
            useDataHookForPay(_fundingCycle),
            useDataHookForRedeem(_fundingCycle),
            dataHook(_fundingCycle),
            metadata(_fundingCycle)
        );
    }
}
