// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PRBMath} from "@paulrberg/contracts/math/PRBMath.sol";
import {JBOperatable} from "./abstract/JBOperatable.sol";
import {JBApprovalStatus} from "./enums/JBApprovalStatus.sol";
import {IJBController} from "./interfaces/IJBController.sol";
import {IJBDirectory} from "./interfaces/IJBDirectory.sol";
import {IJBFundAccessConstraintsStore} from "./interfaces/IJBFundAccessConstraintsStore.sol";
import {IJBRulesets} from "./interfaces/IJBRulesets.sol";
import {IJBMigratable} from "./interfaces/IJBMigratable.sol";
import {IJBOperatable} from "./interfaces/IJBOperatable.sol";
import {IJBOperatorStore} from "./interfaces/IJBOperatorStore.sol";
import {IJBPaymentTerminal} from "./interfaces/IJBPaymentTerminal.sol";
import {IJBProjects} from "./interfaces/IJBProjects.sol";
import {IJBSplitAllocator} from "./interfaces/IJBSplitAllocator.sol";
import {IJBSplitsStore} from "./interfaces/IJBSplitsStore.sol";
import {IJBTokens} from "./interfaces/IJBTokens.sol";
import {JBConstants} from "./libraries/JBConstants.sol";
import {JBRulesetMetadataResolver} from "./libraries/JBRulesetMetadataResolver.sol";
import {JBOperations} from "./libraries/JBOperations.sol";
import {JBSplitsGroups} from "./libraries/JBSplitsGroups.sol";
import {JBRuleset} from "./structs/JBRuleset.sol";
import {JBRulesetConfig} from "./structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "./structs/JBRulesetMetadata.sol";
import {JBProjectMetadata} from "./structs/JBProjectMetadata.sol";
import {JBTerminalConfig} from "./structs/JBTerminalConfig.sol";
import {JBSplit} from "./structs/JBSplit.sol";
import {JBSplitAllocationData} from "./structs/JBSplitAllocationData.sol";

/// @notice Stitches together rulesets and project tokens, making sure all activity is accounted for and correct.
contract JBController is JBOperatable, ERC165, IJBController, IJBMigratable {
    // A library that parses the packed ruleset metadata into a more friendly format.
    using JBRulesetMetadataResolver for JBRuleset;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error BURN_PAUSED_AND_SENDER_NOT_VALID_TERMINAL_DELEGATE();
    error RULESET_ALREADY_LAUNCHED();
    error INVALID_BASE_CURRENCY();
    error INVALID_REDEMPTION_RATE();
    error INVALID_RESERVED_RATE();
    error MIGRATION_NOT_ALLOWED();
    error MINT_NOT_ALLOWED_AND_NOT_TERMINAL_DELEGATE();
    error NO_BURNABLE_TOKENS();
    error NOT_CURRENT_CONTROLLER();
    error ZERO_TOKENS_TO_MINT();

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice Mints ERC-721's that represent project ownership.
    IJBProjects public immutable override projects;

    /// @notice The contract storing all ruleset configurations.
    IJBRulesets public immutable override rulesets;

    /// @notice The contract that manages token minting and burning.
    IJBTokens public immutable override tokenStore;

    /// @notice The contract that stores splits for each project.
    IJBSplitsStore public immutable override splitsStore;

    /// @notice A contract that stores fund access constraints for each project.
    IJBFundAccessConstraintsStore
        public immutable
        override fundAccessConstraintsStore;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable override directory;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The current undistributed reserved token balance of.
    mapping(uint256 => uint256) public override reservedTokenBalanceOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice A project's ruleset for the specified rulesetId along with its metadata.
    /// @param _projectId The ID of the project to which the ruleset belongs.
    /// @return ruleset The ruleset.
    /// @return metadata The ruleset's metadata.
    function getRulesetOf(
        uint256 _projectId,
        uint256 _rulesetId
    )
        external
        view
        override
        returns (
            JBRuleset memory ruleset,
            JBRulesetMetadata memory metadata
        )
    {
        ruleset = rulesets.getRulesetStruct(_projectId, _rulesetId);
        metadata = ruleset.expandMetadata();
    }

    /// @notice A project's latest queued ruleset along with its metadata and the approval status of the configuration.
    /// @param _projectId The ID of the project to which the ruleset belongs.
    /// @return ruleset The latest queued ruleset.
    /// @return metadata The latest queued ruleset's metadata.
    /// @return approvalStatus The approval status of the configuration.
    function latestQueuedRulesetOf(
        uint256 _projectId
    )
        external
        view
        override
        returns (
            JBRuleset memory ruleset,
            JBRulesetMetadata memory metadata,
            JBApprovalStatus approvalStatus
        )
    {
        (ruleset, approvalStatus) = rulesets.latestQueuedOf(_projectId);
        metadata = ruleset.expandMetadata();
    }

    /// @notice A project's current ruleset along with its metadata.
    /// @param _projectId The ID of the project to which the ruleset belongs.
    /// @return ruleset The current ruleset.
    /// @return metadata The current ruleset's metadata.
    function currentRulesetOf(
        uint256 _projectId
    )
        external
        view
        override
        returns (
            JBRuleset memory ruleset,
            JBRulesetMetadata memory metadata
        )
    {
        ruleset = rulesets.currentOf(_projectId);
        metadata = ruleset.expandMetadata();
    }

    /// @notice A project's queued ruleset along with its metadata.
    /// @param _projectId The ID of the project to which the ruleset belongs.
    /// @return ruleset The queued ruleset.
    /// @return metadata The queued ruleset's metadata.
    function queuedRulesetOf(
        uint256 _projectId
    )
        external
        view
        override
        returns (
            JBRuleset memory ruleset,
            JBRulesetMetadata memory metadata
        )
    {
        ruleset = rulesets.upcomingRulesetOf(_projectId);
        metadata = ruleset.expandMetadata();
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice Gets the current total amount of outstanding tokens for a project.
    /// @param _projectId The ID of the project to get total outstanding tokens of.
    /// @return The current total amount of outstanding tokens for the project.
    function totalOutstandingTokensOf(
        uint256 _projectId
    ) public view override returns (uint256) {
        // Add the reserved tokens to the total supply.
        return
            tokenStore.totalSupplyOf(_projectId) +
            reservedTokenBalanceOf[_projectId];
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherance to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            _interfaceId == type(IJBController).interfaceId ||
            _interfaceId == type(IJBMigratable).interfaceId ||
            _interfaceId == type(IJBOperatable).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param _permissions A contract storing operator assignments.
    /// @param _projects A contract which mints ERC-721's that represent project ownership and transfers.
    /// @param _directory A contract storing directories of terminals and controllers for each project.
    /// @param _rulesets A contract storing all ruleset configurations.
    /// @param _tokenStore A contract that manages token minting and burning.
    /// @param _splitsStore A contract that stores splits for each project.
    /// @param _fundAccessConstraintsStore A contract that stores fund access constraints for each project.
    constructor(
        IJBOperatorStore _permissions,
        IJBProjects _projects,
        IJBDirectory _directory,
        IJBRulesets _rulesets,
        IJBTokens _tokenStore,
        IJBSplitsStore _splitsStore,
        IJBFundAccessConstraintsStore _fundAccessConstraintsStore
    ) JBOperatable(_permissions) {
        projects = _projects;
        directory = _directory;
        rulesets = _rulesets;
        tokenStore = _tokenStore;
        splitsStore = _splitsStore;
        fundAccessConstraintsStore = _fundAccessConstraintsStore;
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Creates a project. This will mint an ERC-721 into the specified owner's account, queue a first ruleset, and set up any splits.
    /// @dev Each operation within this transaction can be done in sequence separately.
    /// @dev Anyone can deploy a project on an owner's behalf.
    /// @param _owner The address to set as the owner of the project. The project ERC-721 will be owned by this address.
    /// @param _projectMetadata Metadata to associate with the project within a particular domain. This can be updated any time by the owner of the project.
    /// @param _rulesetConfigurations The ruleset configurations to schedule.
    /// @param _terminalConfigurations The terminal configurations to add for the project.
    /// @param _memo A memo to pass along to the emitted event.
    /// @return projectId The ID of the project.
    function launchProjectFor(
        address _owner,
        JBProjectMetadata calldata _projectMetadata,
        JBRulesetConfig[] calldata _rulesetConfigurations,
        JBTerminalConfig[] calldata _terminalConfigurations,
        string memory _memo
    ) external virtual override returns (uint256 projectId) {
        // Keep a reference to the directory.
        IJBDirectory _directory = directory;

        // Mint the project into the wallet of the owner.
        projectId = projects.createFor(_owner, _projectMetadata);

        // Set this contract as the project's controller in the directory.
        _directory.setControllerOf(projectId, address(this));

        // Queue the first ruleset.
        uint256 _rulesetId = _queueRulesets(
            projectId,
            _rulesetConfigurations
        );

        // Configure the terminals.
        _configureTerminals(projectId, _terminalConfigurations);

        emit LaunchProject(_rulesetId, projectId, _memo, msg.sender);
    }

    /// @notice Creates a ruleset for an already existing project ERC-721.
    /// @dev Each operation within this transaction can be done in sequence separately.
    /// @dev Only a project owner or operator can launch its rulesets.
    /// @param _projectId The ID of the project to launch rulesets for.
    /// @param _rulesetConfigurations The ruleset configurations to schedule.
    /// @param _terminalConfigurations The terminal configurations to add for the project.
    /// @param _memo A memo to pass along to the emitted event.
    /// @return rulesetId The ID of the ruleset that was successfully launched.
    function launchRulesetsFor(
        uint256 _projectId,
        JBRulesetConfig[] calldata _rulesetConfigurations,
        JBTerminalConfig[] calldata _terminalConfigurations,
        string memory _memo
    )
        external
        virtual
        override
        requirePermission(
            projects.ownerOf(_projectId),
            _projectId,
            JBOperations.QUEUE_RULESETS
        )
        returns (uint256 rulesetId)
    {
        // If there is a previous configuration, queueRulesetsOf should be called instead
        if (rulesets.latestRulesetIdOf(_projectId) > 0)
            revert RULESET_ALREADY_LAUNCHED();

        // Set this contract as the project's controller in the directory.
        directory.setControllerOf(_projectId, address(this));

        // Queue the first ruleset.
        rulesetId = _queueRulesets(
            _projectId,
            _rulesetConfigurations
        );

        // Configure the terminals.
        _configureTerminals(_projectId, _terminalConfigurations);

        emit LaunchRulesets(rulesetId, _projectId, _memo, msg.sender);
    }

    /// @notice Queues one or more rulesets that will take effect once the current ruleset expires. Rulesets only take effect if they are approved by the previous ruleset's approval hook.
    /// @dev Only a project's owner or a designated operator can queue rulesets for it.
    /// @param _projectId The ID of the project which rulesets are being queued for.
    /// @param _rulesetConfigurations The configurations of the rulesets to queue.
    /// @param _memo A memo to pass along to the emitted event.
    /// @return rulesetId The rulesetId of the final ruleset which was successfully queued.
    function queueRulesetsOf(
        uint256 _projectId,
        JBRulesetConfig[] calldata _rulesetConfigurations,
        string calldata _memo
    )
        external
        virtual
        override
        requirePermission(
            projects.ownerOf(_projectId),
            _projectId,
            JBOperations.QUEUE_RULESETS
        )
        returns (uint256 rulesetId)
    {
        // Queue the next ruleset.
        rulesetId = _queueRulesets(
            _projectId,
            _rulesetConfigurations
        );

        emit QueueRulesets(
            rulesetId,
            _projectId,
            _memo,
            msg.sender
        );
    }

    /// @notice Mint new token supply into an account, and optionally reserve a supply to be distributed according to the project's current ruleset configuration.
    /// @dev Only a project's owner, a designated operator, one of its terminals, or the current data source can mint its tokens.
    /// @param _projectId The ID of the project to which the tokens being minted belong.
    /// @param _tokenCount The amount of tokens to mint in total, counting however many should be reserved.
    /// @param _beneficiary The account that the tokens are being minted for.
    /// @param _memo A memo to pass along to the emitted event.
    /// @param _useReservedRate Whether to use the current ruleset's reserved rate in the mint calculation.
    /// @return beneficiaryTokenCount The amount of tokens minted for the beneficiary.
    function mintTokensOf(
        uint256 _projectId,
        uint256 _tokenCount,
        address _beneficiary,
        string calldata _memo,
        bool _useReservedRate
    ) external virtual override returns (uint256 beneficiaryTokenCount) {
        // There should be tokens to mint.
        if (_tokenCount == 0) revert ZERO_TOKENS_TO_MINT();

        // Define variables that will be needed outside scoped section below.
        // Keep a reference to the reserved rate to use
        uint256 _reservedRate;

        // Scoped section prevents stack too deep. `_ruleset` only used within scope.
        {
            // Get a reference to the project's current ruleset.
            JBRuleset memory _ruleset = rulesets.currentOf(
                _projectId
            );

            // Minting limited to: project owner, authorized callers, project terminal and current ruleset data source
            _requirePermissionAllowingOverride(
                projects.ownerOf(_projectId),
                _projectId,
                JBOperations.MINT_TOKENS,
                directory.isTerminalOf(
                    _projectId,
                    IJBPaymentTerminal(msg.sender)
                ) || msg.sender == address(_ruleset.dataSource())
            );

            // If the message sender is not a terminal or a datasource, the current ruleset must allow minting.
            if (
                !_ruleset.mintingAllowed() &&
                !directory.isTerminalOf(
                    _projectId,
                    IJBPaymentTerminal(msg.sender)
                ) &&
                msg.sender != address(_ruleset.dataSource())
            ) revert MINT_NOT_ALLOWED_AND_NOT_TERMINAL_DELEGATE();

            // Determine the reserved rate to use.
            _reservedRate = _useReservedRate ? _ruleset.reservedRate() : 0;
        }

        if (_reservedRate != JBConstants.MAX_RESERVED_RATE) {
            // The unreserved token count that will be minted for the beneficiary.
            beneficiaryTokenCount = PRBMath.mulDiv(
                _tokenCount,
                JBConstants.MAX_RESERVED_RATE - _reservedRate,
                JBConstants.MAX_RESERVED_RATE
            );

            // Mint the tokens.
            tokenStore.mintFor(_beneficiary, _projectId, beneficiaryTokenCount);
        }

        // Add reserved tokens if needed
        if (_reservedRate > 0)
            reservedTokenBalanceOf[_projectId] +=
                _tokenCount -
                beneficiaryTokenCount;

        emit MintTokens(
            _beneficiary,
            _projectId,
            _tokenCount,
            beneficiaryTokenCount,
            _memo,
            _reservedRate,
            msg.sender
        );
    }

    /// @notice Burns a token holder's supply.
    /// @dev Only a token's holder, a designated operator, or a project's terminal can burn it.
    /// @param _holder The account that is having its tokens burned.
    /// @param _projectId The ID of the project to which the tokens being burned belong.
    /// @param _tokenCount The number of tokens to burn.
    /// @param _memo A memo to pass along to the emitted event.
    function burnTokensOf(
        address _holder,
        uint256 _projectId,
        uint256 _tokenCount,
        string calldata _memo
    )
        external
        virtual
        override
        requirePermissionAllowingOverride(
            _holder,
            _projectId,
            JBOperations.BURN_TOKENS,
            directory.isTerminalOf(_projectId, IJBPaymentTerminal(msg.sender))
        )
    {
        // There should be tokens to burn
        if (_tokenCount == 0) revert NO_BURNABLE_TOKENS();

        // Burn the tokens.
        tokenStore.burnFrom(_holder, _projectId, _tokenCount);

        emit BurnTokens(_holder, _projectId, _tokenCount, _memo, msg.sender);
    }

    /// @notice Distributes all outstanding reserved tokens for a project.
    /// @param _projectId The ID of the project to which the reserved tokens belong.
    /// @param _memo A memo to pass along to the emitted event.
    /// @return The amount of minted reserved tokens.
    function distributeReservedTokensOf(
        uint256 _projectId,
        string calldata _memo
    ) external virtual override returns (uint256) {
        return _distributeReservedTokensOf(_projectId, _memo);
    }

    /// @notice Allows other controllers to signal to this one that a migration is expected for the specified project.
    /// @dev This controller should not yet be the project's controller.
    /// @param _projectId The ID of the project that will be migrated to this controller.
    /// @param _from The controller being migrated from.
    function prepForMigrationOf(
        uint256 _projectId,
        address _from
    ) external virtual override {
        _projectId; // Prevents unused var compiler and natspec complaints.
        _from; // Prevents unused var compiler and natspec complaints.
    }

    /// @notice Allows a project to migrate from this controller to another.
    /// @dev Only a project's owner or a designated operator can migrate it.
    /// @param _projectId The ID of the project that will be migrated from this controller.
    /// @param _to The controller to which the project is migrating.
    function migrate(
        uint256 _projectId,
        IJBMigratable _to
    )
        external
        virtual
        override
        requirePermission(
            projects.ownerOf(_projectId),
            _projectId,
            JBOperations.MIGRATE_CONTROLLER
        )
    {
        // Keep a reference to the directory.
        IJBDirectory _directory = directory;

        // This controller must be the project's current controller.
        if (_directory.controllerOf(_projectId) != address(this))
            revert NOT_CURRENT_CONTROLLER();

        // Get a reference to the project's current ruleset.
        JBRuleset memory _ruleset = rulesets.currentOf(_projectId);

        // Migration must be allowed.
        if (!_ruleset.controllerMigrationAllowed())
            revert MIGRATION_NOT_ALLOWED();

        // All reserved tokens must be minted before migrating.
        if (reservedTokenBalanceOf[_projectId] != 0)
            _distributeReservedTokensOf(_projectId, "");

        // Make sure the new controller is prepped for the migration.
        _to.prepForMigrationOf(_projectId, address(this));

        // Set the new controller.
        _directory.setControllerOf(_projectId, address(_to));

        emit Migrate(_projectId, _to, msg.sender);
    }

    //*********************************************************************//
    // ------------------------ internal functions ----------------------- //
    //*********************************************************************//

    /// @notice Distributes all outstanding reserved tokens for a project.
    /// @param _projectId The ID of the project to which the reserved tokens belong.
    /// @param _memo A memo to pass along to the emitted event.
    /// @return tokenCount The amount of minted reserved tokens.
    function _distributeReservedTokensOf(
        uint256 _projectId,
        string memory _memo
    ) internal returns (uint256 tokenCount) {
        // Keep a reference to the token store.
        IJBTokens _tokenStore = tokenStore;

        // Get the current ruleset to read the reserved rate from.
        JBRuleset memory _ruleset = rulesets.currentOf(_projectId);

        // Get a reference to the number of tokens that need to be minted.
        tokenCount = reservedTokenBalanceOf[_projectId];

        // Reset the reserved token balance
        reservedTokenBalanceOf[_projectId] = 0;

        // Get a reference to the project owner.
        address _owner = projects.ownerOf(_projectId);

        // Distribute tokens to splits and get a reference to the leftover amount to mint after all splits have gotten their share.
        uint256 _leftoverTokenCount = tokenCount == 0
            ? 0
            : _distributeToReservedTokenSplitsOf(
                _projectId,
                _ruleset.rulesetId,
                JBSplitsGroups.RESERVED_TOKENS,
                tokenCount
            );

        // Mint any leftover tokens to the project owner.
        if (_leftoverTokenCount > 0)
            _tokenStore.mintFor(_owner, _projectId, _leftoverTokenCount);

        emit DistributeReservedTokens(
            _ruleset.rulesetId,
            _ruleset.cycleNumber,
            _projectId,
            _owner,
            tokenCount,
            _leftoverTokenCount,
            _memo,
            msg.sender
        );
    }

    /// @notice Distribute tokens to the splits according to the specified ruleset.
    /// @param _projectId The ID of the project for which reserved token splits are being distributed.
    /// @param _domain The domain of the splits to distribute the reserved tokens between.
    /// @param _group The group of the splits to distribute the reserved tokens between.
    /// @param _amount The total amount of tokens to mint.
    /// @return leftoverAmount If the splits percents dont add up to 100%, the leftover amount is returned.
    function _distributeToReservedTokenSplitsOf(
        uint256 _projectId,
        uint256 _domain,
        uint256 _group,
        uint256 _amount
    ) internal returns (uint256 leftoverAmount) {
        // Keep a reference to the token store.
        IJBTokens _tokenStore = tokenStore;

        // Set the leftover amount to the initial amount.
        leftoverAmount = _amount;

        // Get a reference to the project's reserved token splits.
        JBSplit[] memory _splits = splitsStore.splitsOf(
            _projectId,
            _domain,
            _group
        );

        // Keep a reference to the number of splits being iterated on.
        uint256 _numberOfSplits = _splits.length;

        //Transfer between all splits.
        for (uint256 _i; _i < _numberOfSplits; ) {
            // Get a reference to the split being iterated on.
            JBSplit memory _split = _splits[_i];

            // The amount to send towards the split.
            uint256 _tokenCount = PRBMath.mulDiv(
                _amount,
                _split.percent,
                JBConstants.SPLITS_TOTAL_PERCENT
            );

            // Mints tokens for the split if needed.
            if (_tokenCount > 0) {
                _tokenStore.mintFor(
                    // If an allocator is set in the splits, set it as the beneficiary.
                    // Otherwise if a projectId is set in the split, set the project's owner as the beneficiary.
                    // If the split has a beneficiary send to the split's beneficiary. Otherwise send to the msg.sender.
                    _split.allocator != IJBSplitAllocator(address(0))
                        ? address(_split.allocator)
                        : _split.projectId != 0
                        ? projects.ownerOf(_split.projectId)
                        : _split.beneficiary != address(0)
                        ? _split.beneficiary
                        : msg.sender,
                    _projectId,
                    _tokenCount
                );

                // If there's an allocator set, trigger its `allocate` function.
                if (_split.allocator != IJBSplitAllocator(address(0))) {
                    // Get a reference to the project's token.
                    address _token = address(_tokenStore.tokenOf(_projectId));

                    // Allocate.
                    _split.allocator.allocate(
                        JBSplitAllocationData(
                            _token,
                            _tokenCount,
                            18,
                            _projectId,
                            _group,
                            _split
                        )
                    );
                }

                // Subtract from the amount to be sent to the beneficiary.
                leftoverAmount = leftoverAmount - _tokenCount;
            }

            emit DistributeToReservedTokenSplit(
                _projectId,
                _domain,
                _group,
                _split,
                _tokenCount,
                msg.sender
            );

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice Queues a ruleset and stores information pertinent to the configuration.
    /// @param _projectId The ID of the project whose rulesets are being queued.
    /// @param _rulesetConfigurations The ruleset configurations to schedule.
    /// @return rulesetId The rulesetId of the ruleset that was successfully queued.
    function _queueRulesets(
        uint256 _projectId,
        JBRulesetConfig[] calldata _rulesetConfigurations
    ) internal returns (uint256 rulesetId) {
        // Keep a reference to the configuration being iterated on.
        JBRulesetConfig memory _rulesetId;

        // Keep a reference to the number of configurations being scheduled.
        uint256 _numberOfConfigurations = _rulesetConfigurations.length;

        for (uint256 _i; _i < _numberOfConfigurations; ) {
            // Get a reference to the rulesetId being iterated on.
            _rulesetId = _rulesetConfigurations[_i];

            // Make sure the provided reserved rate is valid.
            if (
                _rulesetId.metadata.reservedRate >
                JBConstants.MAX_RESERVED_RATE
            ) revert INVALID_RESERVED_RATE();

            // Make sure the provided redemption rate is valid.
            if (
                _rulesetId.metadata.redemptionRate >
                JBConstants.MAX_REDEMPTION_RATE
            ) revert INVALID_REDEMPTION_RATE();

            // Make sure the provided base currency is valid.
            if (_rulesetId.metadata.baseCurrency > type(uint32).max)
                revert INVALID_BASE_CURRENCY();

            // Queue the ruleset's properties.
            JBRuleset memory _ruleset = rulesets.queueFor(
                _projectId,
                _rulesetId.data,
                JBRulesetMetadataResolver.packRulesetMetadata(
                    _rulesetId.metadata
                ),
                _rulesetId.mustStartAtOrAfter
            );

            // Set splits for the group.
            splitsStore.set(
                _projectId,
                _ruleset.rulesetId,
                _rulesetId.groupedSplits
            );

            // Set the funds access constraints.
            fundAccessConstraintsStore.setFor(
                _projectId,
                _ruleset.rulesetId,
                _rulesetId.fundAccessConstraints
            );

            // Return the rulesetId timestamp if this is the last configuration being scheduled.
            if (_i == _numberOfConfigurations - 1)
                rulesetId = _ruleset.rulesetId;

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice Configure terminals for use.
    /// @param _projectId The ID of the project configuring the terminals for use.
    /// @param _terminalConfigs The configurations to enact.
    function _configureTerminals(
        uint256 _projectId,
        JBTerminalConfig[] calldata _terminalConfigs
    ) internal {
        // Keep a reference to the number of terminals being configured.
        uint256 _numberOfTerminalConfigs = _terminalConfigs.length;

        // Set a array of terminals to populate.
        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](
            _numberOfTerminalConfigs
        );

        // Keep a reference to the terminal configuration beingiterated on.
        JBTerminalConfig memory _terminalConfig;

        for (uint256 _i; _i < _numberOfTerminalConfigs; ) {
            // Set the terminal configuration being iterated on.
            _terminalConfig = _terminalConfigs[_i];

            // The the accounting contexts.
            _terminalConfig.terminal.setAccountingContextsFor(
                _projectId,
                _terminalConfig.accountingContextConfigs
            );

            // Add the terminal.
            _terminals[_i] = _terminalConfig.terminal;

            unchecked {
                ++_i;
            }
        }

        // Set the terminals in the directory.
        if (_numberOfTerminalConfigs > 0)
            directory.setTerminalsOf(_projectId, _terminals);
    }
}
