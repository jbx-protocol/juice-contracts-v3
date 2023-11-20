// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {JBRulesetMetadata} from "./../structs/JBRulesetMetadata.sol";
import {JBGlobalRulesetMetadata} from "./../structs/JBGlobalRulesetMetadata.sol";

library JBGlobalRulesetMetadataResolver {
    function setTerminalsAllowed(uint8 _data) internal pure returns (bool) {
        return (_data & 1) == 1;
    }

    function setControllerAllowed(uint8 _data) internal pure returns (bool) {
        return ((_data >> 1) & 1) == 1;
    }

    function transfersPaused(uint8 _data) internal pure returns (bool) {
        return ((_data >> 2) & 1) == 1;
    }

    /// @notice Pack the global ruleset metadata.
    /// @param _metadata The metadata to validate and pack.
    /// @return packed The packed uint256 of all global metadata params. The first 8 bits specify the version.
    function packRulesetGlobalMetadata(JBGlobalRulesetMetadata memory _metadata)
        internal
        pure
        returns (uint256 packed)
    {
        // allow set terminals in bit 0.
        if (_metadata.allowSetTerminals) packed |= 1;
        // allow set controller in bit 1.
        if (_metadata.allowSetController) packed |= 1 << 1;
        // pause transfers in bit 2.
        if (_metadata.pauseTransfers) packed |= 1 << 2;
    }

    /// @notice Expand the global ruleset metadata.
    /// @param _packedMetadata The packed metadata to expand.
    /// @return metadata The global metadata object.
    function expandMetadata(uint8 _packedMetadata)
        internal
        pure
        returns (JBGlobalRulesetMetadata memory metadata)
    {
        return JBGlobalRulesetMetadata(
            setTerminalsAllowed(_packedMetadata),
            setControllerAllowed(_packedMetadata),
            transfersPaused(_packedMetadata)
        );
    }
}
