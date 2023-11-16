// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {JBApprovalStatus} from "./../enums/JBApprovalStatus.sol";
import {JBRuleset} from "./../structs/JBRuleset.sol";
import {JBRulesetConfig} from "./../structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "./../structs/JBRulesetMetadata.sol";
import {JBProjectMetadata} from "./../structs/JBProjectMetadata.sol";
import {JBTerminalConfig} from "./../structs/JBTerminalConfig.sol";
import {JBSplit} from "./../structs/JBSplit.sol";
import {IJBDirectory} from "./IJBDirectory.sol";
import {IJBFundAccessConstraintsStore} from "./IJBFundAccessConstraintsStore.sol";
import {IJBRulesets} from "./IJBRulesets.sol";
import {IJBMigratable} from "./IJBMigratable.sol";
import {IJBPaymentTerminal} from "./IJBPaymentTerminal.sol";
import {IJBProjects} from "./IJBProjects.sol";
import {IJBSplitsStore} from "./IJBSplitsStore.sol";
import {IJBTokens} from "./IJBTokens.sol";

interface IJBController is IERC165 {
    event LaunchProject(
        uint256 rulesetId,
        uint256 projectId,
        string memo,
        address caller
    );

    event LaunchRulesets(
        uint256 rulesetId,
        uint256 projectId,
        string memo,
        address caller
    );

    event QueueRulesets(
        uint256 rulesetId,
        uint256 projectId,
        string memo,
        address caller
    );

    event DistributeReservedTokens(
        uint256 indexed rulesetId,
        uint256 indexed rulesetNumber,
        uint256 indexed projectId,
        address beneficiary,
        uint256 tokenCount,
        uint256 beneficiaryTokenCount,
        string memo,
        address caller
    );

    event DistributeToReservedTokenSplit(
        uint256 indexed projectId,
        uint256 indexed domain,
        uint256 indexed group,
        JBSplit split,
        uint256 tokenCount,
        address caller
    );

    event MintTokens(
        address indexed beneficiary,
        uint256 indexed projectId,
        uint256 tokenCount,
        uint256 beneficiaryTokenCount,
        string memo,
        uint256 reservedRate,
        address caller
    );

    event BurnTokens(
        address indexed holder,
        uint256 indexed projectId,
        uint256 tokenCount,
        string memo,
        address caller
    );

    event Migrate(uint256 indexed projectId, IJBMigratable to, address caller);

    event PrepMigration(
        uint256 indexed projectId,
        address from,
        address caller
    );

    function projects() external view returns (IJBProjects);

    function rulesets() external view returns (IJBRulesets);

    function tokenStore() external view returns (IJBTokens);

    function splitsStore() external view returns (IJBSplitsStore);

    function fundAccessConstraintsStore()
        external
        view
        returns (IJBFundAccessConstraintsStore);

    function directory() external view returns (IJBDirectory);

    function reservedTokenBalanceOf(
        uint256 projectId
    ) external view returns (uint256);

    function totalOutstandingTokensOf(
        uint256 projectId
    ) external view returns (uint256);

    function getRulesetOf(
        uint256 projectId,
        uint256 rulesetId
    )
        external
        view
        returns (
            JBRuleset memory ruleset,
            JBRulesetMetadata memory metadata
        );

    function latestQueuedRulesetOf(
        uint256 projectId
    )
        external
        view
        returns (
            JBRuleset memory,
            JBRulesetMetadata memory metadata,
            JBApprovalStatus
        );

    function currentRulesetOf(
        uint256 projectId
    )
        external
        view
        returns (
            JBRuleset memory ruleset,
            JBRulesetMetadata memory metadata
        );

    function queuedRulesetOf(
        uint256 projectId
    )
        external
        view
        returns (
            JBRuleset memory ruleset,
            JBRulesetMetadata memory metadata
        );

    function launchProjectFor(
        address owner,
        JBProjectMetadata calldata projectMetadata,
        JBRulesetConfig[] calldata rulesetConfigurations,
        JBTerminalConfig[] memory terminalConfigurations,
        string calldata memo
    ) external returns (uint256 projectId);

    function launchRulesetsFor(
        uint256 projectId,
        JBRulesetConfig[] calldata rulesetConfigurations,
        JBTerminalConfig[] memory terminalConfigurations,
        string calldata memo
    ) external returns (uint256 rulesetId);

    function queueRulesetsOf(
        uint256 projectId,
        JBRulesetConfig[] calldata rulesetConfigurations,
        string calldata memo
    ) external returns (uint256 rulesetId);

    function mintTokensOf(
        uint256 projectId,
        uint256 tokenCount,
        address beneficiary,
        string calldata memo,
        bool useReservedRate
    ) external returns (uint256 beneficiaryTokenCount);

    function burnTokensOf(
        address holder,
        uint256 projectId,
        uint256 tokenCount,
        string calldata memo
    ) external;

    function distributeReservedTokensOf(
        uint256 projectId,
        string memory memo
    ) external returns (uint256);

    function migrate(uint256 projectId, IJBMigratable to) external;
}
