// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBApprovalStatus} from "./../enums/JBApprovalStatus.sol";
import {JBRuleset} from "./../structs/JBRuleset.sol";
import {JBRulesetData} from "./../structs/JBRulesetData.sol";

interface IJBRulesets {
    event Configure(
        uint256 indexed rulesetId,
        uint256 indexed projectId,
        JBRulesetData data,
        uint256 metadata,
        uint256 mustStartAtOrAfter,
        address caller
    );

    event Init(
        uint256 indexed rulesetId,
        uint256 indexed projectId,
        uint256 indexed basedOn
    );

    function latestRulesetOf(
        uint256 projectId
    ) external view returns (uint256);

    function get(
        uint256 projectId,
        uint256 rulesetId
    ) external view returns (JBRuleset memory);

    function latestConfiguredOf(
        uint256 projectId
    )
        external
        view
        returns (JBRuleset memory ruleset, JBApprovalStatus approvalStatus);

    function queuedOf(
        uint256 projectId
    ) external view returns (JBRuleset memory ruleset);

    function currentOf(
        uint256 projectId
    ) external view returns (JBRuleset memory ruleset);

    function currentApprovalStatusOf(
        uint256 projectId
    ) external view returns (JBApprovalStatus);

    function configureFor(
        uint256 projectId,
        JBRulesetData calldata data,
        uint256 metadata,
        uint256 mustStartAtOrAfter
    ) external returns (JBRuleset memory ruleset);

    function updateRulesetWeightCache(uint256 projectId) external;
}
