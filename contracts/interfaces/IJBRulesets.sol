// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBBallotState} from "./../enums/JBBallotState.sol";
import {JBRuleset} from "./../structs/JBRuleset.sol";
import {JBFundingCycleData} from "./../structs/JBFundingCycleData.sol";

interface IJBRulesets {
    event Configure(
        uint256 indexed rulesetId,
        uint256 indexed projectId,
        JBFundingCycleData data,
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
        returns (JBRuleset memory ruleset, JBBallotState ballotState);

    function queuedOf(
        uint256 projectId
    ) external view returns (JBRuleset memory ruleset);

    function currentOf(
        uint256 projectId
    ) external view returns (JBRuleset memory ruleset);

    function currentBallotStateOf(
        uint256 projectId
    ) external view returns (JBBallotState);

    function configureFor(
        uint256 projectId,
        JBFundingCycleData calldata data,
        uint256 metadata,
        uint256 mustStartAtOrAfter
    ) external returns (JBRuleset memory ruleset);

    function updateFundingCycleWeightCache(uint256 projectId) external;
}
