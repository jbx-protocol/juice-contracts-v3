// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {JBFundAccessConstraints} from "./../structs/JBFundAccessConstraints.sol";
import {JBCurrencyAmount} from "./../structs/JBCurrencyAmount.sol";
import {IJBPayoutTerminal} from "./terminal/IJBPayoutTerminal.sol";

interface IJBFundAccessConstraintsStore is IERC165 {
    event SetFundAccessConstraints(
        uint256 indexed fundingCycleConfiguration,
        uint256 indexed projectId,
        JBFundAccessConstraints constraints,
        address caller
    );

    function distributionLimitsOf(
        uint256 projectId,
        uint256 configuration,
        address terminal,
        address token
    ) external view returns (JBCurrencyAmount[] memory distributionLimits);

    function distributionLimitOf(
        uint256 projectId,
        uint256 configuration,
        address terminal,
        address token,
        uint256 currency
    ) external view returns (uint256 distributionLimit);

    function overflowAllowancesOf(
        uint256 projectId,
        uint256 configuration,
        address terminal,
        address token
    ) external view returns (JBCurrencyAmount[] memory overflowAllowances);

    function overflowAllowanceOf(
        uint256 projectId,
        uint256 configuration,
        address terminal,
        address token,
        uint256 currency
    ) external view returns (uint256 overflowAllowance);

    function setFor(
        uint256 projectId,
        uint256 configuration,
        JBFundAccessConstraints[] memory fundAccessConstaints
    ) external;
}
