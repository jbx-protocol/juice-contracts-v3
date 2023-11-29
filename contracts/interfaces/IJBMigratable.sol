// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IJBMigratable is IERC165 {
    function prepForMigrationOf(uint256 projectId, IERC165 from) external;
}
