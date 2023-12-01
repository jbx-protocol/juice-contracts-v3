// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {JBRuleset} from "./../structs/JBRuleset.sol";
import {JBRulesetMetadata} from "./../structs/JBRulesetMetadata.sol";
import {JBGlobalRulesetMetadata} from "./../structs/JBGlobalRulesetMetadata.sol";
import {JBConstants} from "./JBConstants.sol";
import {JBGlobalRulesetMetadataResolver} from "./JBGlobalRulesetMetadataResolver.sol";

library JBRulesetMetadataResolver {
    function global(JBRuleset memory _ruleset)
        internal
        pure
        returns (JBGlobalRulesetMetadata memory)
    {
        return JBGlobalRulesetMetadataResolver.expandMetadata(uint8(_ruleset.metadata >> 8));
    }

    function reservedRate(JBRuleset memory _ruleset) internal pure returns (uint256) {
        return uint256(uint16(_ruleset.metadata >> 16));
    }

    function redemptionRate(JBRuleset memory _ruleset) internal pure returns (uint256) {
        // Redemption rate is a number 0-10000.
        return uint256(uint16(_ruleset.metadata >> 32));
    }

    function baseCurrency(JBRuleset memory _ruleset) internal pure returns (uint256) {
        // Currency is a number 0-4294967296.
        return uint256(uint32(_ruleset.metadata >> 48));
    }

    function payPaused(JBRuleset memory _ruleset) internal pure returns (bool) {
        return ((_ruleset.metadata >> 80) & 1) == 1;
    }

    function discretionaryMintingAllowed(JBRuleset memory _ruleset) internal pure returns (bool) {
        return ((_ruleset.metadata >> 81) & 1) == 1;
    }

    function terminalMigrationAllowed(JBRuleset memory _ruleset) internal pure returns (bool) {
        return ((_ruleset.metadata >> 82) & 1) == 1;
    }

    function controllerMigrationAllowed(JBRuleset memory _ruleset) internal pure returns (bool) {
        return ((_ruleset.metadata >> 83) & 1) == 1;
    }

    function shouldHoldFees(JBRuleset memory _ruleset) internal pure returns (bool) {
        return ((_ruleset.metadata >> 84) & 1) == 1;
    }

    function useTotalSurplusForRedemptions(JBRuleset memory _ruleset)
        internal
        pure
        returns (bool)
    {
        return ((_ruleset.metadata >> 85) & 1) == 1;
    }

    function useDataHookForPay(JBRuleset memory _ruleset) internal pure returns (bool) {
        return (_ruleset.metadata >> 86) & 1 == 1;
    }

    function useDataHookForRedeem(JBRuleset memory _ruleset) internal pure returns (bool) {
        return (_ruleset.metadata >> 87) & 1 == 1;
    }

    function dataHook(JBRuleset memory _ruleset) internal pure returns (address) {
        return address(uint160(_ruleset.metadata >> 88));
    }

    function metadata(JBRuleset memory _ruleset) internal pure returns (uint256) {
        return uint256(uint8(_ruleset.metadata >> 248));
    }

    /// @notice Pack the ruleset metadata.
    /// @param _metadata The metadata to validate and pack.
    /// @return packed The packed uint256 of all metadata params. The first 8 bits specify the version.
    function packRulesetMetadata(JBRulesetMetadata memory _metadata)
        internal
        pure
        returns (uint256 packed)
    {
        // version 1 in the bits 0-7 (8 bits).
        packed = 1;
        // global metadata in bits 8-15 (8 bits).
        packed |= JBGlobalRulesetMetadataResolver.packRulesetGlobalMetadata(_metadata.global) << 8;
        // reserved rate in bits 16-31 (16 bits).
        packed |= _metadata.reservedRate << 16;
        // redemption rate in bits 32-47 (16 bits).
        // redemption rate is a number 0-10000.
        packed |= _metadata.redemptionRate << 32;
        // base currency in bits 48-79 (32 bits).
        // base currency is a number 0-16777215.
        packed |= _metadata.baseCurrency << 48;
        // pause pay in bit 80.
        if (_metadata.pausePay) packed |= 1 << 80;
        // allow minting in bit 81.
        if (_metadata.allowDiscretionaryMinting) packed |= 1 << 81;
        // allow terminal migration in bit 82.
        if (_metadata.allowTerminalMigration) packed |= 1 << 82;
        // allow controller migration in bit 83.
        if (_metadata.allowControllerMigration) packed |= 1 << 83;
        // hold fees in bit 84.
        if (_metadata.holdFees) packed |= 1 << 84;
        // useTotalSurplusForRedemptions in bit 85.
        if (_metadata.useTotalSurplusForRedemptions) packed |= 1 << 85;
        // use pay data hook in bit 86.
        if (_metadata.useDataHookForPay) packed |= 1 << 86;
        // use redeem data hook in bit 87.
        if (_metadata.useDataHookForRedeem) packed |= 1 << 87;
        // data hook address in bits 88-247.
        packed |= uint256(uint160(address(_metadata.dataHook))) << 88;
        // metadata in bits 248-255 (8 bits).
        packed |= _metadata.metadata << 248;
    }

    /// @notice Expand the ruleset metadata.
    /// @param _ruleset The ruleset having its metadata expanded.
    /// @return metadata The metadata object.
    function expandMetadata(JBRuleset memory _ruleset)
        internal
        pure
        returns (JBRulesetMetadata memory)
    {
        return JBRulesetMetadata(
            global(_ruleset),
            reservedRate(_ruleset),
            redemptionRate(_ruleset),
            baseCurrency(_ruleset),
            payPaused(_ruleset),
            discretionaryMintingAllowed(_ruleset),
            terminalMigrationAllowed(_ruleset),
            controllerMigrationAllowed(_ruleset),
            shouldHoldFees(_ruleset),
            useTotalSurplusForRedemptions(_ruleset),
            useDataHookForPay(_ruleset),
            useDataHookForRedeem(_ruleset),
            dataHook(_ruleset),
            metadata(_ruleset)
        );
    }
}
