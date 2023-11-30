// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBGroupedSplits} from "./../structs/JBGroupedSplits.sol";
import {JBSplit} from "./../structs/JBSplit.sol";
import {IJBDirectory} from "./IJBDirectory.sol";
import {IJBProjects} from "./IJBProjects.sol";
import {IJBControllerUtility} from "./IJBControllerUtility.sol";

interface IJBSplitsStore is IJBControllerUtility {
    event SetSplit(
        uint256 indexed projectId,
        uint256 indexed domain,
        uint256 indexed group,
        JBSplit split,
        address caller
    );

    function splitsOf(uint256 projectId, uint256 domain, uint256 group)
        external
        view
        returns (JBSplit[] memory);

    function set(uint256 projectId, uint256 domain, JBGroupedSplits[] memory groupedSplits)
        external;
}
