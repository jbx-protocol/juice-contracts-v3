// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {PRBMath} from "@paulrberg/contracts/math/PRBMath.sol";
import {JBControllerUtility} from "./abstract/JBControllerUtility.sol";
import {JBApprovalStatus} from "./enums/JBApprovalStatus.sol";
import {JBConstants} from "./libraries/JBConstants.sol";
import {IJBDirectory} from "./interfaces/IJBDirectory.sol";
import {IJBRulesetApprovalHook} from "./interfaces/IJBRulesetApprovalHook.sol";
import {IJBRulesets} from "./interfaces/IJBRulesets.sol";
import {JBRuleset} from "./structs/JBRuleset.sol";
import {JBRulesetData} from "./structs/JBRulesetData.sol";
import {JBRulesetWeightCache} from "./structs/JBRulesetWeightCache.sol";

/// @notice Manages rulesets and queuing.
/// @dev Rulesets dictate how a project behaves for a period of time. To learn more about their functionality, see the `JBRuleset` data structure.
/// @dev Throughout this contract, `rulesetId` is an identifier for each ruleset. The `rulesetId` is the unix timestamp when the ruleset was initialized.
contract JBRulesets is JBControllerUtility, IJBRulesets {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error INVALID_RULESET_APPROVAL_HOOK();
    error INVALID_DECAY_RATE();
    error INVALID_RULESET_DURATION();
    error INVALID_RULESET_END_TIME();
    error INVALID_WEIGHT();
    error BLOCK_ALREADY_CONTAINS_RULESET();

    //*********************************************************************//
    // ------------------------- private constants ----------------------- //
    //*********************************************************************//

    /// @notice The maximum number of decay rate multiples that can be cached at a time.
    uint256 private constant _MAX_DECAY_MULTIPLE_CACHE_THRESHOLD = 50000;

    /// @notice The number of decay rate multiples before a cached value is sought.
    uint256 private constant _DECAY_MULTIPLE_CACHE_LOOKUP_THRESHOLD = 1000;

    //*********************************************************************//
    // --------------------- private stored properties ------------------- //
    //*********************************************************************//

    /// @notice The user-defined properties of each ruleset, packed into one storage slot.
    /// @custom:param _projectId The ID of the project to get the user-defined properties of.
    /// @custom:param _rulesetId The ID of the ruleset to get the user-defined properties of.
    mapping(uint256 => mapping(uint256 => uint256))
        private _packedUserPropertiesOf;

    /// @notice The mechanism-added properties to manage and schedule each ruleset, packed into one storage slot.
    /// @custom:param _projectId The ID of the project to get the intrinsic properties of.
    /// @custom:param _rulesetId The ID of the ruleset to get the intrinsic properties of.
    mapping(uint256 => mapping(uint256 => uint256))
        private _packedIntrinsicPropertiesOf;

    /// @notice The metadata for each ruleset, packed into one storage slot.
    /// @custom:param _projectId The ID of the project to get metadata of.
    /// @custom:param _rulesetId The ID of the ruleset to get metadata of.
    mapping(uint256 => mapping(uint256 => uint256)) private _metadataOf;

    /// @notice Cached weight values to derive rulesets from.
    /// @custom:param _projectId The ID of the project to which the cache applies.
    mapping(uint256 => JBRulesetWeightCache) internal _weightCache;
    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The ID of the ruleset with the latest start time for a specific project, whether the ruleset has been approved or not.
    /// @dev If a project has multiple rulesets queued, the `latestRulesetIdOf` will be the last one.
    /// @custom:param _projectId The ID of the project to get the latest ruleset ID of.
    /// @return latestRulesetIdOf The `rulesetId` of the project's latest ruleset.
    mapping(uint256 => uint256) public override latestRulesetIdOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Get the ruleset struct for a given `rulesetId` and `projectId`.
    /// @param _projectId The ID of the project to which the ruleset belongs.
    /// @param _rulesetId The ID of the ruleset to get the struct of.
    /// @return ruleset The ruleset struct.
    function getRulesetStruct(
        uint256 _projectId,
        uint256 _rulesetId
    ) external view override returns (JBRuleset memory ruleset) {
        return _getStructFor(_projectId, _rulesetId);
    }

    /// @notice The latest ruleset queued for a project. Returns the ruleset's struct and its current approval status.
    /// @param _projectId The ID of the project to get the latest queued ruleset of.
    /// @return ruleset The project's latest queued ruleset's struct.
    /// @return approvalStatus The approval hook's status for the ruleset.
    function latestQueuedOf(
        uint256 _projectId
    )
        external
        view
        override
        returns (JBRuleset memory ruleset, JBApprovalStatus approvalStatus)
    {
        // Get a reference to the latest ruleset's ID.
        uint256 _rulesetId = latestRulesetIdOf[_projectId];

        // Resolve the struct for the latest ruleset.
        ruleset = _getStructFor(_projectId, _rulesetId);

        // Resolve the approval status.
        approvalStatus = _approvalStatusOf(
            _projectId,
            ruleset.rulesetId,
            ruleset.start,
            ruleset.basedOn
        );
    }

    /// @notice The ruleset that's up next for a project.
    /// @dev If an upcoming ruleset is not found for the project, returns an empty ruleset with all properties set to 0.
    /// @param _projectId The ID of the project to get the upcoming ruleset of.
    /// @return ruleset The project's upcoming ruleset.
    function upcomingRulesetOf(
        uint256 _projectId
    ) external view override returns (JBRuleset memory ruleset) {
        // If the project does not have a latest ruleset, return an empty struct.
        if (latestRulesetIdOf[_projectId] == 0) return _getStructFor(0, 0);

        // Get a reference to the ID of the next approvable ruleset.
        uint256 _nextApprovableRulesetId = _nextApprovableRulesetIdOf(_projectId);

        // Keep a reference to the approval status.
        JBApprovalStatus _approvalStatus;

        // If it exists, return its ruleset if it is approved.
        if (_nextApprovableRulesetId != 0) {
            ruleset = _getStructFor(
                _projectId,
                _nextApprovableRulesetId
            );

            // Get a reference to the approval status.
            _approvalStatus = _approvalStatusOf(_projectId, ruleset);

            // If the approval hook hasn't failed, return it.
            if (
                _approvalStatus == JBApprovalStatus.Approved ||
                _approvalStatus == JBApprovalStatus.ApprovalExpected ||
                _approvalStatus == JBApprovalStatus.Empty
            ) return ruleset;

            // Resolve the ruleset for the latest queued ruleset.
            ruleset = _getStructFor(_projectId, ruleset.basedOn);
        } else {
            // Resolve the ruleset for the latest queued ruleset.
            ruleset = _getStructFor(
                _projectId,
                latestRulesetIdOf[_projectId]
            );

            // If the latest ruleset starts in the future, it must start in the distant future
            // since its not in standby. In this case base the queued ruleset on the base ruleset.
            while (ruleset.start > block.timestamp) {
                ruleset = _getStructFor(_projectId, ruleset.basedOn);
            }
        }

        // There's no queued if the current has a duration of 0.
        if (ruleset.duration == 0) return _getStructFor(0, 0);

        // Get a reference to the approval status.
        _approvalStatus = _approvalStatusOf(_projectId, ruleset);

        // Check to see if this ruleset's approval hook hasn't failed.
        // If so, return a ruleset based on it.
        if (
            _approvalStatus == JBApprovalStatus.Approved ||
            _approvalStatus == JBApprovalStatus.Empty
        ) return _mockRulesetBasedOn(ruleset, false);

        // Get the ruleset of its base ruleset, which carries the last approved configuration.
        ruleset = _getStructFor(_projectId, ruleset.basedOn);

        // There's no queued if the base, which must still be the current, has a duration of 0.
        if (ruleset.duration == 0) return _getStructFor(0, 0);

        // Return a mock of the next up ruleset.
        return _mockRulesetBasedOn(ruleset, false);
    }

    /// @notice The ruleset that is currently active for the specified project.
    /// @dev If a current ruleset of the project is not found, returns an empty ruleset with all properties set to 0.
    /// @param _projectId The ID of the project to get the current ruleset of.
    /// @return ruleset The project's current ruleset.
    function currentOf(
        uint256 _projectId
    ) external view override returns (JBRuleset memory ruleset) {
        // If the project does not have a ruleset, return an empty struct.
        if (latestRulesetIdOf[_projectId] == 0) return _getStructFor(0, 0);

        // Get a reference to the currently approvable ruleset's ID.
        uint256 _rulesetId = _currentlyApprovableRulesetOf(_projectId);

        // Keep a reference to the currently approvable ruleset's struct.
        JBRuleset memory _ruleset;

        // If a currently approvable ruleset exists...
        if (_rulesetId != 0) {
            // Resolve the struct for the currently approvable ruleset.
            _ruleset = _getStructFor(
                _projectId,
                _rulesetId
            );

            // Get a reference to the approval status.
            JBApprovalStatus _approvalStatus = _approvalStatusOf(
                _projectId,
                _ruleset
            );

            // Check to see if this ruleset's approval hook is approved if it exists.
            // If so, return it.
            if (
                _approvalStatus == JBApprovalStatus.Approved ||
                _approvalStatus == JBApprovalStatus.Empty
            ) return _ruleset;

            // If it hasn't been approved, set the ruleset configuration to be the configuration of the ruleset that it's based on,
            // which carries the last approved configuration.
            _rulesetId = _ruleset.basedOn;

            // Keep a reference to its ruleset.
            _ruleset = _getStructFor(
                _projectId,
                _rulesetId
            );
        } else {
            // No upcoming ruleset found that is currently approvable,
            // so use the latest ruleset ID.
            _rulesetId = latestRulesetIdOf[_projectId];

            // Get the struct for the latest ID.
            _ruleset = _getStructFor(
                _projectId,
                _rulesetId
            );

            // Get a reference to the approval status.
            JBApprovalStatus _approvalStatus = _approvalStatusOf(
                _projectId,
                _ruleset
            );

            // While the ruleset has a approval hook that isn't approved or if it hasn't yet started, get a reference to the ruleset that the latest is based on, which has the latest approved configuration.
            while (
                (_approvalStatus != JBApprovalStatus.Approved &&
                    _approvalStatus != JBApprovalStatus.Empty) ||
                block.timestamp < _ruleset.start
            ) {
                _rulesetId = _ruleset.basedOn;
                _ruleset = _getStructFor(
                    _projectId,
                    _rulesetId
                );
                _approvalStatus = _approvalStatusOf(_projectId, _ruleset);
            }
        }

        // If the base has no duration, it's still the current one.
        if (_ruleset.duration == 0) return _ruleset;

        // Return a mock of the current ruleset.
        return _mockRulesetBasedOn(_ruleset, true);
    }

    /// @notice The current approval status of the project.
    /// @param _projectId The ID of the project to check the approval status of.
    /// @return The project's current approval status.
    function currentApprovalStatusOf(
        uint256 _projectId
    ) external view override returns (JBApprovalStatus) {
        // Get a reference to the latest ruleset configuration.
        uint256 _rulesetId = latestRulesetIdOf[_projectId];

        // Resolve the ruleset for the latest configuration.
        JBRuleset memory _ruleset = _getStructFor(
            _projectId,
            _rulesetId
        );

        return
            _approvalStatusOf(
                _projectId,
                _ruleset.rulesetId,
                _ruleset.start,
                _ruleset.basedOn
            );
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param _directory A contract storing directories of terminals and controllers for each project.
    // solhint-disable-next-line no-empty-blocks
    constructor(IJBDirectory _directory) JBControllerUtility(_directory) {}

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Queues the next approvable ruleset for the specified project.
    /// @dev Only a project's current controller can queue its rulesets.
    /// @param _projectId The ID of the project being queued.
    /// @param _data The ruleset configuration data.
    /// @param _metadata Arbitrary extra data to associate with this ruleset configuration that's not used within.
    /// @param _mustStartAtOrAfter The time before which the initialized ruleset cannot start.
    /// @return The ruleset that the configuration will take effect during.
    function queueFor(
        uint256 _projectId,
        JBRulesetData calldata _data,
        uint256 _metadata,
        uint256 _mustStartAtOrAfter
    )
        external
        override
        onlyController(_projectId)
        returns (JBRuleset memory)
    {
        // Duration must fit in a uint32.
        if (_data.duration > type(uint32).max) revert INVALID_RULESET_DURATION();

        // decay rate must be less than or equal to 100%.
        if (_data.decayRate > JBConstants.MAX_DECAY_RATE)
            revert INVALID_DECAY_RATE();

        // Weight must fit into a uint88.
        if (_data.weight > type(uint88).max) revert INVALID_WEIGHT();

        // If the start date is in the past, set it to be the current timestamp.
        if (_mustStartAtOrAfter < block.timestamp)
            _mustStartAtOrAfter = block.timestamp;

        // Make sure the min start date fits in a uint56, and that the start date of an upcoming ruleset also starts within the max.
        if (_mustStartAtOrAfter + _data.duration > type(uint56).max)
            revert INVALID_RULESET_END_TIME();

        // approval hook should be a valid contract, supporting the correct interface
        if (_data.approvalHook != IJBRulesetApprovalHook(address(0))) {
            address _approvalHook = address(_data.approvalHook);

            // No contract at the address ?
            if (_approvalHook.code.length == 0) revert INVALID_RULESET_APPROVAL_HOOK();

            // Make sure the approval hook supports the expected interface.
            try
                _data.approvalHook.supportsInterface(
                    type(IJBRulesetApprovalHook).interfaceId
                )
            returns (bool _supports) {
                if (!_supports) revert INVALID_RULESET_APPROVAL_HOOK(); // Contract exists at the address but with the wrong interface
            } catch {
                revert INVALID_RULESET_APPROVAL_HOOK(); // No ERC165 support
            }
        }

        // Get a reference to the latest configration.
        uint256 _latestId = latestRulesetIdOf[_projectId];

        // The rulesetId timestamp is now, or an increment from now if the current timestamp is taken.
        uint256 _rulesetId = _latestId >= block.timestamp
            ? _latestId + 1
            : block.timestamp;

        // Set up a reconfiguration by configuring intrinsic properties.
        _configureIntrinsicPropertiesFor(
            _projectId,
            _rulesetId,
            _data.weight,
            _mustStartAtOrAfter
        );

        // Efficiently stores rulesets provided user defined properties.
        // If all user config properties are zero, no need to store anything as the default value will have the same outcome.
        if (
            _data.approvalHook != IJBRulesetApprovalHook(address(0)) ||
            _data.duration > 0 ||
            _data.decayRate > 0
        ) {
            // approval hook in bits 0-159 bytes.
            uint256 packed = uint160(address(_data.approvalHook));

            // duration in bits 160-191 bytes.
            packed |= _data.duration << 160;

            // decayRate in bits 192-223 bytes.
            packed |= _data.decayRate << 192;

            // Set in storage.
            _packedUserPropertiesOf[_projectId][_rulesetId] = packed;
        }

        // Set the metadata if needed.
        if (_metadata > 0) _metadataOf[_projectId][_rulesetId] = _metadata;

        emit RulesetQueued(
            _rulesetId,
            _projectId,
            _data,
            _metadata,
            _mustStartAtOrAfter,
            msg.sender
        );

        // Return the ruleset for the new configuration.
        return _getStructFor(_projectId, _rulesetId);
    }

    /// @notice Cache the value of the ruleset weight.
    /// @param _projectId The ID of the project having its ruleset weight cached.
    function updateRulesetWeightCache(
        uint256 _projectId
    ) external override {
        // Keep a reference to the latest queued ruleset, from which the cached value will be based.
        JBRuleset memory _latestQueuedRuleset = _getStructFor(
            _projectId,
            latestRulesetIdOf[_projectId]
        );

        // Nothing to cache if the latest configuration doesn't have a duration or a decay rate.
        if (
            _latestQueuedRuleset.duration == 0 ||
            _latestQueuedRuleset.decayRate == 0
        ) return;

        // Get a reference to the current cache.
        JBRulesetWeightCache storage _cache = _weightCache[
            _latestQueuedRuleset.rulesetId
        ];

        // Determine the max start timestamp from which the cache can be set.
        uint256 _maxStart = _latestQueuedRuleset.start +
            (_cache.decayMultiple + _MAX_DECAY_MULTIPLE_CACHE_THRESHOLD) *
            _latestQueuedRuleset.duration;

        // Determine the timestamp from the which the cache will be set.
        uint256 _start = block.timestamp < _maxStart
            ? block.timestamp
            : _maxStart;

        // The difference between the start of the base ruleset and the proposed start.
        uint256 _startDistance = _start - _latestQueuedRuleset.start;

        // Determine the decay multiple that'll be cached.
        uint256 _decayMultiple;
        unchecked {
            _decayMultiple =
                _startDistance /
                _latestQueuedRuleset.duration;
        }

        // Store the new values.
        _cache.weight = _deriveWeightFrom(
            _latestQueuedRuleset,
            _start
        );
        _cache.decayMultiple = _decayMultiple;
    }

    //*********************************************************************//
    // --------------------- private helper functions -------------------- //
    //*********************************************************************//

    /// @notice Updates the configurable ruleset for this project if it exists, otherwise creates one.
    /// @param _projectId The ID of the project to find a configurable ruleset for.
    /// @param _rulesetId The time at which the ruleset was queued.
    /// @param _weight The weight to store in the queued ruleset.
    /// @param _mustStartAtOrAfter The time before which the initialized ruleset can't start.
    function _configureIntrinsicPropertiesFor(
        uint256 _projectId,
        uint256 _rulesetId,
        uint256 _weight,
        uint256 _mustStartAtOrAfter
    ) private {
        // Keep a reference to the project's latest configuration.
        uint256 _latestId = latestRulesetIdOf[_projectId];

        // If there's not yet a ruleset for the project, initialize one.
        if (_latestId == 0)
            // Use an empty ruleset as the base.
            return
                _initializeRulesetFor(
                    _projectId,
                    _getStructFor(0, 0),
                    _rulesetId,
                    _mustStartAtOrAfter,
                    _weight
                );

        // Get a reference to the ruleset.
        JBRuleset memory _baseRuleset = _getStructFor(
            _projectId,
            _latestId
        );

        // Get a reference to the approval status.
        JBApprovalStatus _approvalStatus = _approvalStatusOf(
            _projectId,
            _baseRuleset
        );

        // If the base ruleset has started but wasn't approved if a approval hook exists OR it hasn't started but is currently approved OR it hasn't started but it is likely to be approved and takes place before the proposed one, set the ID to be the ruleset it's based on,
        // which carries the latest approved configuration.
        if (
            (block.timestamp >= _baseRuleset.start &&
                _approvalStatus != JBApprovalStatus.Approved &&
                _approvalStatus != JBApprovalStatus.Empty) ||
            (block.timestamp < _baseRuleset.start &&
                _mustStartAtOrAfter <
                _baseRuleset.start + _baseRuleset.duration &&
                _approvalStatus != JBApprovalStatus.Approved) ||
            (block.timestamp < _baseRuleset.start &&
                _mustStartAtOrAfter >=
                _baseRuleset.start + _baseRuleset.duration &&
                _approvalStatus != JBApprovalStatus.Approved &&
                _approvalStatus != JBApprovalStatus.ApprovalExpected &&
                _approvalStatus != JBApprovalStatus.Empty)
        )
            _baseRuleset = _getStructFor(
                _projectId,
                _baseRuleset.basedOn
            );

        // The rulesetId can't be the same as the base rulesetId.
        if (_baseRuleset.rulesetId == _rulesetId)
            revert BLOCK_ALREADY_CONTAINS_RULESET();

        // The time after the approval hook of the provided ruleset has expired.
        // If the provided ruleset has no approval hook, return the current timestamp.
        uint256 _timestampAfterBallot = _baseRuleset.approvalHook ==
            IJBRulesetApprovalHook(address(0))
            ? 0
            : _rulesetId + _baseRuleset.approvalHook.duration();

        _initializeRulesetFor(
            _projectId,
            _baseRuleset,
            _rulesetId,
            // Can only start after the approval hook.
            _timestampAfterBallot > _mustStartAtOrAfter
                ? _timestampAfterBallot
                : _mustStartAtOrAfter,
            _weight
        );
    }

    /// @notice Initializes a ruleset with the specified properties.
    /// @param _projectId The ID of the project to which the ruleset being initialized belongs.
    /// @param _baseRuleset The ruleset to base the initialized one on.
    /// @param _rulesetId The rulesetId of the ruleset being initialized.
    /// @param _mustStartAtOrAfter The time before which the initialized ruleset cannot start.
    /// @param _weight The weight to give the newly initialized ruleset.
    function _initializeRulesetFor(
        uint256 _projectId,
        JBRuleset memory _baseRuleset,
        uint256 _rulesetId,
        uint256 _mustStartAtOrAfter,
        uint256 _weight
    ) private {
        // If there is no base, initialize a first ruleset.
        if (_baseRuleset.cycleNumber == 0) {
            // The first number is 1.
            uint256 _cycleNumber = 1;

            // Set fresh intrinsic properties.
            _packAndStoreIntrinsicPropertiesOf(
                _rulesetId,
                _projectId,
                _cycleNumber,
                _weight,
                _baseRuleset.rulesetId,
                _mustStartAtOrAfter
            );
        } else {
            // Derive the correct next start time from the base.
            uint256 _start = _deriveStartFrom(
                _baseRuleset,
                _mustStartAtOrAfter
            );

            // A weight of 1 is treated as a weight of 0.
            // This is to allow a weight of 0 (default) to represent inheriting the decayed weight of the previous ruleset.
            _weight = _weight > 0
                ? (_weight == 1 ? 0 : _weight)
                : _deriveWeightFrom(_baseRuleset, _start);

            // Derive the correct number.
            uint256 _cycleNumber = _deriveNumberFrom(_baseRuleset, _start);

            // Update the intrinsic properties.
            _packAndStoreIntrinsicPropertiesOf(
                _rulesetId,
                _projectId,
                _cycleNumber,
                _weight,
                _baseRuleset.rulesetId,
                _start
            );
        }

        // Set the project's latest ruleset configuration.
        latestRulesetIdOf[_projectId] = _rulesetId;

        emit RulesetInitialized(_rulesetId, _projectId, _baseRuleset.rulesetId);
    }

    /// @notice Efficiently stores a ruleset's provided intrinsic properties.
    /// @param _rulesetId The rulesetId of the ruleset to pack and store.
    /// @param _projectId The ID of the project to which the ruleset belongs.
    /// @param _cycleNumber The number of the ruleset.
    /// @param _weight The weight of the ruleset.
    /// @param _basedOn The rulesetId of the base ruleset.
    /// @param _start The start time of this ruleset.
    function _packAndStoreIntrinsicPropertiesOf(
        uint256 _rulesetId,
        uint256 _projectId,
        uint256 _cycleNumber,
        uint256 _weight,
        uint256 _basedOn,
        uint256 _start
    ) private {
        // weight in bits 0-87.
        uint256 packed = _weight;

        // basedOn in bits 88-143.
        packed |= _basedOn << 88;

        // start in bits 144-199.
        packed |= _start << 144;

        // number in bits 200-255.
        packed |= _cycleNumber << 200;

        // Store the packed value.
        _packedIntrinsicPropertiesOf[_projectId][_rulesetId] = packed;
    }

    /// @notice The project's stored ruleset that hasn't yet started and should be used next, if one exists.
    /// @dev A value of 0 is returned if no ruleset was found.
    /// @dev Assumes the project has a latest configuration.
    /// @param _projectId The ID of a project to look through for a standby ruleset.
    /// @return rulesetId The rulesetId of the standby ruleset if one exists, or 0 if one doesn't exist.
    function _nextApprovableRulesetIdOf(
        uint256 _projectId
    ) private view returns (uint256 rulesetId) {
        // Get a reference to the project's latest ruleset.
        rulesetId = latestRulesetIdOf[_projectId];

        // Get the necessary properties for the latest ruleset.
        JBRuleset memory _ruleset = _getStructFor(
            _projectId,
            rulesetId
        );

        // There is no upcoming ruleset if the latest ruleset has already started.
        if (block.timestamp >= _ruleset.start) return 0;

        // If this is the first ruleset, it is queued.
        if (_ruleset.cycleNumber == 1) return rulesetId;

        // Get a reference to the base rulesetId.
        uint256 _basedOnId = _ruleset.basedOn;

        // Get the necessary properties for the base ruleset.
        JBRuleset memory _baseRuleset;

        // Find the base ruleset that is not still queued.
        while (true) {
            _baseRuleset = _getStructFor(
                _projectId,
                _basedOnId
            );

            if (block.timestamp < _baseRuleset.start) {
                // Set the rulesetId to the one found.
                rulesetId = _baseRuleset.rulesetId;
                // Prepare the next ruleset's configuration to check in the next iteration.
                _basedOnId = _baseRuleset.basedOn;
                // Break out of the loop when a started base ruleset is found.
            } else break;
        }

        // Get the ruleset for the configuration.
        _ruleset = _getStructFor(_projectId, rulesetId);

        // If the latest configuration doesn't start until after another base ruleset return 0.
        if (
            _baseRuleset.duration != 0 &&
            block.timestamp < _ruleset.start - _baseRuleset.duration
        ) return 0;
    }

    /// @notice The project's stored ruleset that has started and hasn't yet expired. If approved, this is the active ruleset.
    /// @dev A value of 0 is returned if no ruleset was found.
    /// @dev Assumes the project has a latest configuration.
    /// @param _projectId The ID of the project to look through.
    /// @return The rulesetId of a currently approvable ruleset if one exists, or 0 if one doesn't exist.
    function _currentlyApprovableRulesetOf(uint256 _projectId) private view returns (uint256) {
        // Get a reference to the project's latest ruleset.
        uint256 _rulesetId = latestRulesetIdOf[_projectId];

        // Get the latest ruleset.
        JBRuleset memory _ruleset = _getStructFor(
            _projectId,
            _rulesetId
        );

        // Loop through all most recently queued rulesets until an approvable one is found, or we've proven one can't exist.
        do {
            // If the latest is expired, return an empty ruleset.
            // A duration of 0 cannot be expired.
            if (
                _ruleset.duration != 0 &&
                block.timestamp >= _ruleset.start + _ruleset.duration
            ) return 0;

            // Return the ruleset's rulesetId if it has started.
            if (block.timestamp >= _ruleset.start)
                return _ruleset.rulesetId;

            _ruleset = _getStructFor(_projectId, _ruleset.basedOn);
        } while (_ruleset.cycleNumber != 0);

        return 0;
    }

    /// @notice A view of the ruleset that would be created based on the provided one if the project doesn't make a rerulesetId.
    /// @dev Returns an empty ruleset if there can't be a mock ruleset based on the provided one.
    /// @dev Assumes a ruleset with a duration of 0 will never be asked to be the base of a mock.
    /// @param _baseRuleset The ruleset that the resulting ruleset should follow.
    /// @param _allowMidRuleset A flag indicating if the mocked ruleset is allowed to already be mid ruleset.
    /// @return A mock of what the next ruleset will be.
    function _mockRulesetBasedOn(
        JBRuleset memory _baseRuleset,
        bool _allowMidRuleset
    ) private view returns (JBRuleset memory) {
        // Get the distance of the current time to the start of the next possible ruleset.
        // If the returned mock ruleset must not yet have started, the start time of the mock must be in the future.
        uint256 _mustStartAtOrAfter = !_allowMidRuleset
            ? block.timestamp + 1
            : block.timestamp - _baseRuleset.duration + 1;

        // Derive what the start time should be.
        uint256 _start = _deriveStartFrom(
            _baseRuleset,
            _mustStartAtOrAfter
        );

        // Derive what the number should be.
        uint256 _cycleNumber = _deriveNumberFrom(_baseRuleset, _start);

        return
            JBRuleset(
                _cycleNumber,
                _baseRuleset.rulesetId,
                _baseRuleset.basedOn,
                _start,
                _baseRuleset.duration,
                _deriveWeightFrom(_baseRuleset, _start),
                _baseRuleset.decayRate,
                _baseRuleset.approvalHook,
                _baseRuleset.metadata
            );
    }

    /// @notice The date that is the nearest multiple of the specified ruleset's duration from its end.
    /// @param _baseRuleset The ruleset to base the calculation on.
    /// @param _mustStartAtOrAfter A date that the derived start must be on or come after.
    /// @return start The next start time.
    function _deriveStartFrom(
        JBRuleset memory _baseRuleset,
        uint256 _mustStartAtOrAfter
    ) private pure returns (uint256 start) {
        // A subsequent ruleset to one with a duration of 0 should start as soon as possible.
        if (_baseRuleset.duration == 0) return _mustStartAtOrAfter;

        // The time when the ruleset immediately after the specified ruleset starts.
        uint256 _nextImmediateStart = _baseRuleset.start +
            _baseRuleset.duration;

        // If the next immediate start is now or in the future, return it.
        if (_nextImmediateStart >= _mustStartAtOrAfter)
            return _nextImmediateStart;

        // The amount of seconds since the `_mustStartAtOrAfter` time which results in a start time that might satisfy the specified constraints.
        uint256 _timeFromImmediateStartMultiple = (_mustStartAtOrAfter -
            _nextImmediateStart) % _baseRuleset.duration;

        // A reference to the first possible start timestamp.
        start = _mustStartAtOrAfter - _timeFromImmediateStartMultiple;

        // Add increments of duration as necessary to satisfy the threshold.
        while (_mustStartAtOrAfter > start)
            start = start + _baseRuleset.duration;
    }

    /// @notice The accumulated weight change since the specified ruleset.
    /// @param _baseRuleset The ruleset to base the calculation on.
    /// @param _start The start time of the ruleset to derive a number for.
    /// @return weight The derived weight, as a fixed point number with 18 decimals.
    function _deriveWeightFrom(
        JBRuleset memory _baseRuleset,
        uint256 _start
    ) private view returns (uint256 weight) {
        // A subsequent ruleset to one with a duration of 0 should have the next possible weight.
        if (_baseRuleset.duration == 0)
            return
                PRBMath.mulDiv(
                    _baseRuleset.weight,
                    JBConstants.MAX_DECAY_RATE -
                        _baseRuleset.decayRate,
                    JBConstants.MAX_DECAY_RATE
                );

        // The weight should be based off the base ruleset's weight.
        weight = _baseRuleset.weight;

        // If the decay is 0, the weight doesn't change.
        if (_baseRuleset.decayRate == 0) return weight;

        // The difference between the start of the base ruleset and the proposed start.
        uint256 _startDistance = _start - _baseRuleset.start;

        // Apply the base ruleset's decay rate for each ruleset that has passed.
        uint256 _decayMultiple;
        unchecked {
            _decayMultiple = _startDistance / _baseRuleset.duration; // Non-null duration is excluded above
        }

        // Check the cache if needed.
        if (_decayMultiple > _DECAY_MULTIPLE_CACHE_LOOKUP_THRESHOLD) {
            // Get a cached weight for the rulesetId.
            JBRulesetWeightCache memory _cache = _weightCache[
                _baseRuleset.rulesetId
            ];

            // If a cached value is available, use it.
            if (_cache.decayMultiple > 0) {
                // Set the starting weight to be the cached value.
                weight = _cache.weight;

                // Set the decay multiple to be the difference between the cached value and the total decay multiple that should be applied.
                _decayMultiple -= _cache.decayMultiple;
            }
        }

        for (uint256 _i; _i < _decayMultiple; ) {
            // The number of times to apply the decay rate.
            // Base the new weight on the specified ruleset's weight.
            weight = PRBMath.mulDiv(
                weight,
                JBConstants.MAX_DECAY_RATE - _baseRuleset.decayRate,
                JBConstants.MAX_DECAY_RATE
            );

            // The calculation doesn't need to continue if the weight is 0.
            if (weight == 0) break;

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice The number of the next ruleset given the specified ruleset.
    /// @param _baseRuleset The ruleset to base the calculation on.
    /// @param _start The start time of the ruleset to derive a number for.
    /// @return The ruleset number.
    function _deriveNumberFrom(
        JBRuleset memory _baseRuleset,
        uint256 _start
    ) private pure returns (uint256) {
        // A subsequent ruleset to one with a duration of 0 should be the next number.
        if (_baseRuleset.duration == 0)
            return _baseRuleset.cycleNumber + 1;

        // The difference between the start of the base ruleset and the proposed start.
        uint256 _startDistance = _start - _baseRuleset.start;

        // Find the number of base rulesets that fit in the start distance.
        return
            _baseRuleset.cycleNumber +
            (_startDistance / _baseRuleset.duration);
    }

    /// @notice Checks to see if the provided ruleset is approved according to the correct approval hook.
    /// @param _projectId The ID of the project to which the ruleset belongs.
    /// @param _ruleset The ruleset to get an approval flag for.
    /// @return The approval status of the project.
    function _approvalStatusOf(
        uint256 _projectId,
        JBRuleset memory _ruleset
    ) private view returns (JBApprovalStatus) {
        return
            _approvalStatusOf(
                _projectId,
                _ruleset.rulesetId,
                _ruleset.start,
                _ruleset.basedOn
            );
    }

    /// @notice A project's latest ruleset configuration approval status.
    /// @param _projectId The ID of the project to which the ruleset belongs.
    /// @param _rulesetId The ruleset configuration to get the approval status of.
    /// @param _start The start time of the ruleset configuration to get the approval status of.
    /// @param _approvalHookRulesetId The configuration of the ruleset which is queued with the approval hook that should be used.
    /// @return The approval status of the project.
    function _approvalStatusOf(
        uint256 _projectId,
        uint256 _rulesetId,
        uint256 _start,
        uint256 _approvalHookRulesetId
    ) private view returns (JBApprovalStatus) {
        // If there is no approval hook ruleset, the approval hook is empty.
        if (_approvalHookRulesetId == 0) return JBApprovalStatus.Empty;

        // Get the approval hook ruleset.
        JBRuleset memory _approvalHookRuleset = _getStructFor(
            _projectId,
            _approvalHookRulesetId
        );

        // If there is no approval hook, it's considered empty.
        if (_approvalHookRuleset.approvalHook == IJBRulesetApprovalHook(address(0)))
            return JBApprovalStatus.Empty;

        // Return the approval hook's state
        return
            _approvalHookRuleset.approvalHook.approvalStatusOf(
                _projectId,
                _rulesetId,
                _start
            );
    }

    /// @notice Unpack a ruleset's packed stored values into an easy-to-work-with ruleset struct.
    /// @param _projectId The ID of the project to which the ruleset belongs.
    /// @param _rulesetId The ruleset rulesetId to get the full struct for.
    /// @return ruleset A ruleset struct.
    function _getStructFor(
        uint256 _projectId,
        uint256 _rulesetId
    ) private view returns (JBRuleset memory ruleset) {
        // Return an empty ruleset if the rulesetId specified is 0.
        if (_rulesetId == 0) return ruleset;

        ruleset.rulesetId = _rulesetId;

        uint256 _packedIntrinsicProperties = _packedIntrinsicPropertiesOf[
            _projectId
        ][_rulesetId];

        // weight in bits 0-87 bits.
        ruleset.weight = uint256(uint88(_packedIntrinsicProperties));
        // basedOn in bits 88-143 bits.
        ruleset.basedOn = uint256(
            uint56(_packedIntrinsicProperties >> 88)
        );
        // start in bits 144-199 bits.
        ruleset.start = uint256(uint56(_packedIntrinsicProperties >> 144));
        // number in bits 200-255 bits.
        ruleset.cycleNumber = uint256(
            uint56(_packedIntrinsicProperties >> 200)
        );

        uint256 _packedUserProperties = _packedUserPropertiesOf[_projectId][
            _rulesetId
        ];

        // approval hook in bits 0-159 bits.
        ruleset.approvalHook = IJBRulesetApprovalHook(
            address(uint160(_packedUserProperties))
        );
        // duration in bits 160-191 bits.
        ruleset.duration = uint256(uint32(_packedUserProperties >> 160));
        // decayRate in bits 192-223 bits.
        ruleset.decayRate = uint256(
            uint32(_packedUserProperties >> 192)
        );

        ruleset.metadata = _metadataOf[_projectId][_rulesetId];
    }
}
