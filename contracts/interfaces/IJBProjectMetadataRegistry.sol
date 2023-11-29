// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBProjectMetadata} from "./../structs/JBProjectMetadata.sol";

interface IJBProjectMetadataRegistry {
    function metadataContentOf(uint256 projectId, uint256 domain)
        external
        view
        returns (string memory);

    function setMetadataOf(uint256 projectId, JBProjectMetadata calldata metadata) external;
}
