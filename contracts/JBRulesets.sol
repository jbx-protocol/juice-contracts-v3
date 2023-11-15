// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {PRBMath} from "@paulrberg/contracts/math/PRBMath.sol";
import {JBControllerUtility} from "./abstract/JBControllerUtility.sol";
import {JBBallotState} from "./enums/JBBallotState.sol";
import {JBConstants} from "./libraries/JBConstants.sol";
import {IJBDirectory} from "./interfaces/IJBDirectory.sol";
import {IJBFundingCycleBallot} from "./interfaces/IJBFundingCycleBallot.sol";
import {IJBRulesets} from "./interfaces/IJBRulesets.sol";
import {JBRuleset} from "./structs/JBRuleset.sol";
import {JBFundingCycleData} from "./structs/JBFundingCycleData.sol";
import {JBFundingCycleWeightCache} from "./structs/JBFundingCycleWeightCache.sol";

/// @notice Manages rulesets and queuing.
/// @dev TODO: Ruleset/queuing explanation
/// @dev TODO: rulesetId explanation
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

    /// @notice The max number of decay rate multiples that can be cached at a time.
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
    mapping(uint256 => JBFundingCycleWeightCache) internal _weightCache;
    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The ruleset with the latest start time for a project, whether it has been approved or not.
    /// @dev If a project has queued multiple rulesets, the latestRulesetOf will be the rulesetId of the last one.
    /// @custom:param _projectId The ID of the project to get the latest ruleset of.
    /// @return latestRulesetOf The rulesetId of the project's latest ruleset.
    mapping(uint256 => uint256) public override latestRulesetOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Get the ruleset struct for a given rulesetId and projectId.
    /// @param _projectId The ID of the project to which the ruleset belongs.
    /// @param _rulesetId The ID of the ruleset to get the struct of.
    /// @return ruleset The funding cycle.
    function get(
        uint256 _projectId,
        uint256 _rulesetId
    ) external view override returns (JBRuleset memory ruleset) {
        return _getStructFor(_projectId, _rulesetId);
    }

    /// @notice The latest funding cycle to be configured for the specified project, and its current ballot state.
    /// @param _projectId The ID of the project to get the latest configured funding cycle of.
    /// @return ruleset The project's queued funding cycle.
    /// @return ballotState The state of the ballot for the reconfiguration.
    function latestConfiguredOf(
        uint256 _projectId
    )
        external
        view
        override
        returns (JBRuleset memory ruleset, JBBallotState ballotState)
    {
        // Get a reference to the latest funding cycle configuration.
        uint256 _fundingCycleConfiguration = latestRulesetOf[_projectId];

        // Resolve the funding cycle for the latest configuration.
        ruleset = _getStructFor(_projectId, _fundingCycleConfiguration);

        // Resolve the ballot state.
        ballotState = _ballotStateOf(
            _projectId,
            ruleset.rulesetId,
            ruleset.start,
            ruleset.basedOn
        );
    }

    /// @notice The funding cycle that's next up for the specified project.
    /// @dev If a queued funding cycle of the project is not found, returns an empty funding cycle with all properties set to 0.
    /// @param _projectId The ID of the project to get the queued funding cycle of.
    /// @return ruleset The project's queued funding cycle.
    function queuedOf(
        uint256 _projectId
    ) external view override returns (JBRuleset memory ruleset) {
        // If the project does not have a funding cycle, return an empty struct.
        if (latestRulesetOf[_projectId] == 0) return _getStructFor(0, 0);

        // Get a reference to the rulesetId of the standby funding cycle.
        uint256 _standbyFundingCycleConfiguration = _standbyOf(_projectId);

        // Keep a reference to the ballot state.
        JBBallotState _ballotState;

        // If it exists, return its funding cycle if it is approved.
        if (_standbyFundingCycleConfiguration != 0) {
            ruleset = _getStructFor(
                _projectId,
                _standbyFundingCycleConfiguration
            );

            // Get a reference to the ballot state.
            _ballotState = _ballotStateOf(_projectId, ruleset);

            // If the ballot hasn't failed, return it.
            if (
                _ballotState == JBBallotState.Approved ||
                _ballotState == JBBallotState.ApprovalExpected ||
                _ballotState == JBBallotState.Empty
            ) return ruleset;

            // Resolve the funding cycle for the latest configured funding cycle.
            ruleset = _getStructFor(_projectId, ruleset.basedOn);
        } else {
            // Resolve the funding cycle for the latest configured funding cycle.
            ruleset = _getStructFor(
                _projectId,
                latestRulesetOf[_projectId]
            );

            // If the latest funding cycle starts in the future, it must start in the distant future
            // since its not in standby. In this case base the queued cycles on the base cycle.
            while (ruleset.start > block.timestamp) {
                ruleset = _getStructFor(_projectId, ruleset.basedOn);
            }
        }

        // There's no queued if the current has a duration of 0.
        if (ruleset.duration == 0) return _getStructFor(0, 0);

        // Get a reference to the ballot state.
        _ballotState = _ballotStateOf(_projectId, ruleset);

        // Check to see if this funding cycle's ballot hasn't failed.
        // If so, return a funding cycle based on it.
        if (
            _ballotState == JBBallotState.Approved ||
            _ballotState == JBBallotState.Empty
        ) return _mockFundingCycleBasedOn(ruleset, false);

        // Get the funding cycle of its base funding cycle, which carries the last approved configuration.
        ruleset = _getStructFor(_projectId, ruleset.basedOn);

        // There's no queued if the base, which must still be the current, has a duration of 0.
        if (ruleset.duration == 0) return _getStructFor(0, 0);

        // Return a mock of the next up funding cycle.
        return _mockFundingCycleBasedOn(ruleset, false);
    }

    /// @notice The funding cycle that is currently active for the specified project.
    /// @dev If a current funding cycle of the project is not found, returns an empty funding cycle with all properties set to 0.
    /// @param _projectId The ID of the project to get the current funding cycle of.
    /// @return ruleset The project's current funding cycle.
    function currentOf(
        uint256 _projectId
    ) external view override returns (JBRuleset memory ruleset) {
        // If the project does not have a funding cycle, return an empty struct.
        if (latestRulesetOf[_projectId] == 0) return _getStructFor(0, 0);

        // Get a reference to the rulesetId of the eligible funding cycle.
        uint256 _fundingCycleConfiguration = _eligibleOf(_projectId);

        // Keep a reference to the eligible funding cycle.
        JBRuleset memory _ruleset;

        // If an eligible funding cycle exists...
        if (_fundingCycleConfiguration != 0) {
            // Resolve the funding cycle for the eligible configuration.
            _ruleset = _getStructFor(
                _projectId,
                _fundingCycleConfiguration
            );

            // Get a reference to the ballot state.
            JBBallotState _ballotState = _ballotStateOf(
                _projectId,
                _ruleset
            );

            // Check to see if this funding cycle's ballot is approved if it exists.
            // If so, return it.
            if (
                _ballotState == JBBallotState.Approved ||
                _ballotState == JBBallotState.Empty
            ) return _ruleset;

            // If it hasn't been approved, set the funding cycle configuration to be the configuration of the funding cycle that it's based on,
            // which carries the last approved configuration.
            _fundingCycleConfiguration = _ruleset.basedOn;

            // Keep a reference to its funding cycle.
            _ruleset = _getStructFor(
                _projectId,
                _fundingCycleConfiguration
            );
        } else {
            // No upcoming funding cycle found that is eligible to become active,
            // so use the last configuration.
            _fundingCycleConfiguration = latestRulesetOf[_projectId];

            // Get the funding cycle for the latest ID.
            _ruleset = _getStructFor(
                _projectId,
                _fundingCycleConfiguration
            );

            // Get a reference to the ballot state.
            JBBallotState _ballotState = _ballotStateOf(
                _projectId,
                _ruleset
            );

            // While the cycle has a ballot that isn't approved or if it hasn't yet started, get a reference to the funding cycle that the latest is based on, which has the latest approved configuration.
            while (
                (_ballotState != JBBallotState.Approved &&
                    _ballotState != JBBallotState.Empty) ||
                block.timestamp < _ruleset.start
            ) {
                _fundingCycleConfiguration = _ruleset.basedOn;
                _ruleset = _getStructFor(
                    _projectId,
                    _fundingCycleConfiguration
                );
                _ballotState = _ballotStateOf(_projectId, _ruleset);
            }
        }

        // If the base has no duration, it's still the current one.
        if (_ruleset.duration == 0) return _ruleset;

        // Return a mock of the current funding cycle.
        return _mockFundingCycleBasedOn(_ruleset, true);
    }

    /// @notice The current ballot state of the project.
    /// @param _projectId The ID of the project to check the ballot state of.
    /// @return The project's current ballot's state.
    function currentBallotStateOf(
        uint256 _projectId
    ) external view override returns (JBBallotState) {
        // Get a reference to the latest funding cycle configuration.
        uint256 _fundingCycleConfiguration = latestRulesetOf[_projectId];

        // Resolve the funding cycle for the latest configuration.
        JBRuleset memory _ruleset = _getStructFor(
            _projectId,
            _fundingCycleConfiguration
        );

        return
            _ballotStateOf(
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

    /// @notice Configures the next eligible funding cycle for the specified project.
    /// @dev Only a project's current controller can configure its funding cycles.
    /// @param _projectId The ID of the project being configured.
    /// @param _data The funding cycle configuration data.
    /// @param _metadata Arbitrary extra data to associate with this funding cycle configuration that's not used within.
    /// @param _mustStartAtOrAfter The time before which the initialized funding cycle cannot start.
    /// @return The funding cycle that the configuration will take effect during.
    function configureFor(
        uint256 _projectId,
        JBFundingCycleData calldata _data,
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

        // Make sure the min start date fits in a uint56, and that the start date of an upcoming cycle also starts within the max.
        if (_mustStartAtOrAfter + _data.duration > type(uint56).max)
            revert INVALID_RULESET_END_TIME();

        // Ballot should be a valid contract, supporting the correct interface
        if (_data.ballot != IJBFundingCycleBallot(address(0))) {
            address _ballot = address(_data.ballot);

            // No contract at the address ?
            if (_ballot.code.length == 0) revert INVALID_RULESET_APPROVAL_HOOK();

            // Make sure the ballot supports the expected interface.
            try
                _data.ballot.supportsInterface(
                    type(IJBFundingCycleBallot).interfaceId
                )
            returns (bool _supports) {
                if (!_supports) revert INVALID_RULESET_APPROVAL_HOOK(); // Contract exists at the address but with the wrong interface
            } catch {
                revert INVALID_RULESET_APPROVAL_HOOK(); // No ERC165 support
            }
        }

        // Get a reference to the latest configration.
        uint256 _latestConfiguration = latestRulesetOf[_projectId];

        // The rulesetId timestamp is now, or an increment from now if the current timestamp is taken.
        uint256 _rulesetId = _latestConfiguration >= block.timestamp
            ? _latestConfiguration + 1
            : block.timestamp;

        // Set up a reconfiguration by configuring intrinsic properties.
        _configureIntrinsicPropertiesFor(
            _projectId,
            _rulesetId,
            _data.weight,
            _mustStartAtOrAfter
        );

        // Efficiently stores a funding cycles provided user defined properties.
        // If all user config properties are zero, no need to store anything as the default value will have the same outcome.
        if (
            _data.ballot != IJBFundingCycleBallot(address(0)) ||
            _data.duration > 0 ||
            _data.decayRate > 0
        ) {
            // ballot in bits 0-159 bytes.
            uint256 packed = uint160(address(_data.ballot));

            // duration in bits 160-191 bytes.
            packed |= _data.duration << 160;

            // decayRate in bits 192-223 bytes.
            packed |= _data.decayRate << 192;

            // Set in storage.
            _packedUserPropertiesOf[_projectId][_rulesetId] = packed;
        }

        // Set the metadata if needed.
        if (_metadata > 0) _metadataOf[_projectId][_rulesetId] = _metadata;

        emit Configure(
            _rulesetId,
            _projectId,
            _data,
            _metadata,
            _mustStartAtOrAfter,
            msg.sender
        );

        // Return the funding cycle for the new configuration.
        return _getStructFor(_projectId, _rulesetId);
    }

    /// @notice Cache the value of the funding cycle weight.
    /// @param _projectId The ID of the project having its funding cycle weight cached.
    function updateFundingCycleWeightCache(
        uint256 _projectId
    ) external override {
        // Keep a reference to the latest configured funding cycle, from which the cached value will be based.
        JBRuleset memory _latestConfiguredFundingCycle = _getStructFor(
            _projectId,
            latestRulesetOf[_projectId]
        );

        // Nothing to cache if the latest configuration doesn't have a duration or a decay rate.
        if (
            _latestConfiguredFundingCycle.duration == 0 ||
            _latestConfiguredFundingCycle.decayRate == 0
        ) return;

        // Get a reference to the current cache.
        JBFundingCycleWeightCache storage _cache = _weightCache[
            _latestConfiguredFundingCycle.rulesetId
        ];

        // Determine the max start timestamp from which the cache can be set.
        uint256 _maxStart = _latestConfiguredFundingCycle.start +
            (_cache.decayMultiple + _MAX_DECAY_MULTIPLE_CACHE_THRESHOLD) *
            _latestConfiguredFundingCycle.duration;

        // Determine the timestamp from the which the cache will be set.
        uint256 _start = block.timestamp < _maxStart
            ? block.timestamp
            : _maxStart;

        // The difference between the start of the base funding cycle and the proposed start.
        uint256 _startDistance = _start - _latestConfiguredFundingCycle.start;

        // Determine the decay multiple that'll be cached.
        uint256 _decayMultiple;
        unchecked {
            _decayMultiple =
                _startDistance /
                _latestConfiguredFundingCycle.duration;
        }

        // Store the new values.
        _cache.weight = _deriveWeightFrom(
            _latestConfiguredFundingCycle,
            _start
        );
        _cache.decayMultiple = _decayMultiple;
    }

    //*********************************************************************//
    // --------------------- private helper functions -------------------- //
    //*********************************************************************//

    /// @notice Updates the configurable funding cycle for this project if it exists, otherwise creates one.
    /// @param _projectId The ID of the project to find a configurable funding cycle for.
    /// @param _rulesetId The time at which the funding cycle was configured.
    /// @param _weight The weight to store in the configured funding cycle.
    /// @param _mustStartAtOrAfter The time before which the initialized funding cycle can't start.
    function _configureIntrinsicPropertiesFor(
        uint256 _projectId,
        uint256 _rulesetId,
        uint256 _weight,
        uint256 _mustStartAtOrAfter
    ) private {
        // Keep a reference to the project's latest configuration.
        uint256 _latestConfiguration = latestRulesetOf[_projectId];

        // If there's not yet a funding cycle for the project, initialize one.
        if (_latestConfiguration == 0)
            // Use an empty funding cycle as the base.
            return
                _initFor(
                    _projectId,
                    _getStructFor(0, 0),
                    _rulesetId,
                    _mustStartAtOrAfter,
                    _weight
                );

        // Get a reference to the funding cycle.
        JBRuleset memory _baseFundingCycle = _getStructFor(
            _projectId,
            _latestConfiguration
        );

        // Get a reference to the ballot state.
        JBBallotState _ballotState = _ballotStateOf(
            _projectId,
            _baseFundingCycle
        );

        // If the base funding cycle has started but wasn't approved if a ballot exists OR it hasn't started but is currently approved OR it hasn't started but it is likely to be approved and takes place before the proposed one, set the ID to be the funding cycle it's based on,
        // which carries the latest approved configuration.
        if (
            (block.timestamp >= _baseFundingCycle.start &&
                _ballotState != JBBallotState.Approved &&
                _ballotState != JBBallotState.Empty) ||
            (block.timestamp < _baseFundingCycle.start &&
                _mustStartAtOrAfter <
                _baseFundingCycle.start + _baseFundingCycle.duration &&
                _ballotState != JBBallotState.Approved) ||
            (block.timestamp < _baseFundingCycle.start &&
                _mustStartAtOrAfter >=
                _baseFundingCycle.start + _baseFundingCycle.duration &&
                _ballotState != JBBallotState.Approved &&
                _ballotState != JBBallotState.ApprovalExpected &&
                _ballotState != JBBallotState.Empty)
        )
            _baseFundingCycle = _getStructFor(
                _projectId,
                _baseFundingCycle.basedOn
            );

        // The rulesetId can't be the same as the base rulesetId.
        if (_baseFundingCycle.rulesetId == _rulesetId)
            revert BLOCK_ALREADY_CONTAINS_RULESET();

        // The time after the ballot of the provided funding cycle has expired.
        // If the provided funding cycle has no ballot, return the current timestamp.
        uint256 _timestampAfterBallot = _baseFundingCycle.ballot ==
            IJBFundingCycleBallot(address(0))
            ? 0
            : _rulesetId + _baseFundingCycle.ballot.duration();

        _initFor(
            _projectId,
            _baseFundingCycle,
            _rulesetId,
            // Can only start after the ballot.
            _timestampAfterBallot > _mustStartAtOrAfter
                ? _timestampAfterBallot
                : _mustStartAtOrAfter,
            _weight
        );
    }

    /// @notice Initializes a funding cycle with the specified properties.
    /// @param _projectId The ID of the project to which the funding cycle being initialized belongs.
    /// @param _baseFundingCycle The funding cycle to base the initialized one on.
    /// @param _rulesetId The rulesetId of the funding cycle being initialized.
    /// @param _mustStartAtOrAfter The time before which the initialized funding cycle cannot start.
    /// @param _weight The weight to give the newly initialized funding cycle.
    function _initFor(
        uint256 _projectId,
        JBRuleset memory _baseFundingCycle,
        uint256 _rulesetId,
        uint256 _mustStartAtOrAfter,
        uint256 _weight
    ) private {
        // If there is no base, initialize a first cycle.
        if (_baseFundingCycle.cycleNumber == 0) {
            // The first number is 1.
            uint256 _cycleNumber = 1;

            // Set fresh intrinsic properties.
            _packAndStoreIntrinsicPropertiesOf(
                _rulesetId,
                _projectId,
                _cycleNumber,
                _weight,
                _baseFundingCycle.rulesetId,
                _mustStartAtOrAfter
            );
        } else {
            // Derive the correct next start time from the base.
            uint256 _start = _deriveStartFrom(
                _baseFundingCycle,
                _mustStartAtOrAfter
            );

            // A weight of 1 is treated as a weight of 0.
            // This is to allow a weight of 0 (default) to represent inheriting the decayed weight of the previous funding cycle.
            _weight = _weight > 0
                ? (_weight == 1 ? 0 : _weight)
                : _deriveWeightFrom(_baseFundingCycle, _start);

            // Derive the correct number.
            uint256 _cycleNumber = _deriveNumberFrom(_baseFundingCycle, _start);

            // Update the intrinsic properties.
            _packAndStoreIntrinsicPropertiesOf(
                _rulesetId,
                _projectId,
                _cycleNumber,
                _weight,
                _baseFundingCycle.rulesetId,
                _start
            );
        }

        // Set the project's latest funding cycle configuration.
        latestRulesetOf[_projectId] = _rulesetId;

        emit Init(_rulesetId, _projectId, _baseFundingCycle.rulesetId);
    }

    /// @notice Efficiently stores a funding cycle's provided intrinsic properties.
    /// @param _rulesetId The rulesetId of the funding cycle to pack and store.
    /// @param _projectId The ID of the project to which the funding cycle belongs.
    /// @param _cycleNumber The number of the funding cycle.
    /// @param _weight The weight of the funding cycle.
    /// @param _basedOn The rulesetId of the base funding cycle.
    /// @param _start The start time of this funding cycle.
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

    /// @notice The project's stored funding cycle that hasn't yet started and should be used next, if one exists.
    /// @dev A value of 0 is returned if no funding cycle was found.
    /// @dev Assumes the project has a latest configuration.
    /// @param _projectId The ID of a project to look through for a standby cycle.
    /// @return rulesetId The rulesetId of the standby funding cycle if one exists, or 0 if one doesn't exist.
    function _standbyOf(
        uint256 _projectId
    ) private view returns (uint256 rulesetId) {
        // Get a reference to the project's latest funding cycle.
        rulesetId = latestRulesetOf[_projectId];

        // Get the necessary properties for the latest funding cycle.
        JBRuleset memory _ruleset = _getStructFor(
            _projectId,
            rulesetId
        );

        // There is no upcoming funding cycle if the latest funding cycle has already started.
        if (block.timestamp >= _ruleset.start) return 0;

        // If this is the first funding cycle, it is queued.
        if (_ruleset.cycleNumber == 1) return rulesetId;

        // Get a reference to the base rulesetId.
        uint256 _basedOnConfiguration = _ruleset.basedOn;

        // Get the necessary properties for the base funding cycle.
        JBRuleset memory _baseFundingCycle;

        // Find the base cycle that is not still queued.
        while (true) {
            _baseFundingCycle = _getStructFor(
                _projectId,
                _basedOnConfiguration
            );

            if (block.timestamp < _baseFundingCycle.start) {
                // Set the rulesetId to the one found.
                rulesetId = _baseFundingCycle.rulesetId;
                // Prepare the next funding cycle's configuration to check in the next iteration.
                _basedOnConfiguration = _baseFundingCycle.basedOn;
                // Break out of the loop when a started base funding cycle is found.
            } else break;
        }

        // Get the funding cycle for the configuration.
        _ruleset = _getStructFor(_projectId, rulesetId);

        // If the latest configuration doesn't start until after another base cycle, return 0.
        if (
            _baseFundingCycle.duration != 0 &&
            block.timestamp < _ruleset.start - _baseFundingCycle.duration
        ) return 0;
    }

    /// @notice The project's stored funding cycle that has started and hasn't yet expired.
    /// @dev A value of 0 is returned if no funding cycle was found.
    /// @dev Assumes the project has a latest configuration.
    /// @param _projectId The ID of the project to look through.
    /// @return The rulesetId of an eligible funding cycle if one exists, or 0 if one doesn't exist.
    function _eligibleOf(uint256 _projectId) private view returns (uint256) {
        // Get a reference to the project's latest funding cycle.
        uint256 _rulesetId = latestRulesetOf[_projectId];

        // Get the latest funding cycle.
        JBRuleset memory _ruleset = _getStructFor(
            _projectId,
            _rulesetId
        );

        // Loop through all most recently configured funding cycles until an eligible one is found, or we've proven one can't exist.
        do {
            // If the latest is expired, return an empty funding cycle.
            // A duration of 0 cannot be expired.
            if (
                _ruleset.duration != 0 &&
                block.timestamp >= _ruleset.start + _ruleset.duration
            ) return 0;

            // Return the funding cycle's rulesetId if it has started.
            if (block.timestamp >= _ruleset.start)
                return _ruleset.rulesetId;

            _ruleset = _getStructFor(_projectId, _ruleset.basedOn);
        } while (_ruleset.cycleNumber != 0);

        return 0;
    }

    /// @notice A view of the funding cycle that would be created based on the provided one if the project doesn't make a rerulesetId.
    /// @dev Returns an empty funding cycle if there can't be a mock funding cycle based on the provided one.
    /// @dev Assumes a funding cycle with a duration of 0 will never be asked to be the base of a mock.
    /// @param _baseFundingCycle The funding cycle that the resulting funding cycle should follow.
    /// @param _allowMidCycle A flag indicating if the mocked funding cycle is allowed to already be mid cycle.
    /// @return A mock of what the next funding cycle will be.
    function _mockFundingCycleBasedOn(
        JBRuleset memory _baseFundingCycle,
        bool _allowMidCycle
    ) private view returns (JBRuleset memory) {
        // Get the distance of the current time to the start of the next possible funding cycle.
        // If the returned mock cycle must not yet have started, the start time of the mock must be in the future.
        uint256 _mustStartAtOrAfter = !_allowMidCycle
            ? block.timestamp + 1
            : block.timestamp - _baseFundingCycle.duration + 1;

        // Derive what the start time should be.
        uint256 _start = _deriveStartFrom(
            _baseFundingCycle,
            _mustStartAtOrAfter
        );

        // Derive what the number should be.
        uint256 _cycleNumber = _deriveNumberFrom(_baseFundingCycle, _start);

        return
            JBRuleset(
                _cycleNumber,
                _baseFundingCycle.rulesetId,
                _baseFundingCycle.basedOn,
                _start,
                _baseFundingCycle.duration,
                _deriveWeightFrom(_baseFundingCycle, _start),
                _baseFundingCycle.decayRate,
                _baseFundingCycle.ballot,
                _baseFundingCycle.metadata
            );
    }

    /// @notice The date that is the nearest multiple of the specified funding cycle's duration from its end.
    /// @param _baseFundingCycle The funding cycle to base the calculation on.
    /// @param _mustStartAtOrAfter A date that the derived start must be on or come after.
    /// @return start The next start time.
    function _deriveStartFrom(
        JBRuleset memory _baseFundingCycle,
        uint256 _mustStartAtOrAfter
    ) private pure returns (uint256 start) {
        // A subsequent cycle to one with a duration of 0 should start as soon as possible.
        if (_baseFundingCycle.duration == 0) return _mustStartAtOrAfter;

        // The time when the funding cycle immediately after the specified funding cycle starts.
        uint256 _nextImmediateStart = _baseFundingCycle.start +
            _baseFundingCycle.duration;

        // If the next immediate start is now or in the future, return it.
        if (_nextImmediateStart >= _mustStartAtOrAfter)
            return _nextImmediateStart;

        // The amount of seconds since the `_mustStartAtOrAfter` time which results in a start time that might satisfy the specified constraints.
        uint256 _timeFromImmediateStartMultiple = (_mustStartAtOrAfter -
            _nextImmediateStart) % _baseFundingCycle.duration;

        // A reference to the first possible start timestamp.
        start = _mustStartAtOrAfter - _timeFromImmediateStartMultiple;

        // Add increments of duration as necessary to satisfy the threshold.
        while (_mustStartAtOrAfter > start)
            start = start + _baseFundingCycle.duration;
    }

    /// @notice The accumulated weight change since the specified funding cycle.
    /// @param _baseFundingCycle The funding cycle to base the calculation on.
    /// @param _start The start time of the funding cycle to derive a number for.
    /// @return weight The derived weight, as a fixed point number with 18 decimals.
    function _deriveWeightFrom(
        JBRuleset memory _baseFundingCycle,
        uint256 _start
    ) private view returns (uint256 weight) {
        // A subsequent cycle to one with a duration of 0 should have the next possible weight.
        if (_baseFundingCycle.duration == 0)
            return
                PRBMath.mulDiv(
                    _baseFundingCycle.weight,
                    JBConstants.MAX_DECAY_RATE -
                        _baseFundingCycle.decayRate,
                    JBConstants.MAX_DECAY_RATE
                );

        // The weight should be based off the base funding cycle's weight.
        weight = _baseFundingCycle.weight;

        // If the decay is 0, the weight doesn't change.
        if (_baseFundingCycle.decayRate == 0) return weight;

        // The difference between the start of the base funding cycle and the proposed start.
        uint256 _startDistance = _start - _baseFundingCycle.start;

        // Apply the base funding cycle's decay rate for each cycle that has passed.
        uint256 _decayMultiple;
        unchecked {
            _decayMultiple = _startDistance / _baseFundingCycle.duration; // Non-null duration is excluded above
        }

        // Check the cache if needed.
        if (_decayMultiple > _DECAY_MULTIPLE_CACHE_LOOKUP_THRESHOLD) {
            // Get a cached weight for the rulesetId.
            JBFundingCycleWeightCache memory _cache = _weightCache[
                _baseFundingCycle.rulesetId
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
            // Base the new weight on the specified funding cycle's weight.
            weight = PRBMath.mulDiv(
                weight,
                JBConstants.MAX_DECAY_RATE - _baseFundingCycle.decayRate,
                JBConstants.MAX_DECAY_RATE
            );

            // The calculation doesn't need to continue if the weight is 0.
            if (weight == 0) break;

            unchecked {
                ++_i;
            }
        }
    }

    /// @notice The number of the next funding cycle given the specified funding cycle.
    /// @param _baseFundingCycle The funding cycle to base the calculation on.
    /// @param _start The start time of the funding cycle to derive a number for.
    /// @return The funding cycle number.
    function _deriveNumberFrom(
        JBRuleset memory _baseFundingCycle,
        uint256 _start
    ) private pure returns (uint256) {
        // A subsequent cycle to one with a duration of 0 should be the next number.
        if (_baseFundingCycle.duration == 0)
            return _baseFundingCycle.cycleNumber + 1;

        // The difference between the start of the base funding cycle and the proposed start.
        uint256 _startDistance = _start - _baseFundingCycle.start;

        // Find the number of base cycles that fit in the start distance.
        return
            _baseFundingCycle.cycleNumber +
            (_startDistance / _baseFundingCycle.duration);
    }

    /// @notice Checks to see if the provided funding cycle is approved according to the correct ballot.
    /// @param _projectId The ID of the project to which the funding cycle belongs.
    /// @param _ruleset The funding cycle to get an approval flag for.
    /// @return The ballot state of the project.
    function _ballotStateOf(
        uint256 _projectId,
        JBRuleset memory _ruleset
    ) private view returns (JBBallotState) {
        return
            _ballotStateOf(
                _projectId,
                _ruleset.rulesetId,
                _ruleset.start,
                _ruleset.basedOn
            );
    }

    /// @notice A project's latest funding cycle configuration approval status.
    /// @param _projectId The ID of the project to which the funding cycle belongs.
    /// @param _rulesetId The funding cycle configuration to get the ballot state of.
    /// @param _start The start time of the funding cycle configuration to get the ballot state of.
    /// @param _ballotFundingCycleConfiguration The configuration of the funding cycle which is configured with the ballot that should be used.
    /// @return The ballot state of the project.
    function _ballotStateOf(
        uint256 _projectId,
        uint256 _rulesetId,
        uint256 _start,
        uint256 _ballotFundingCycleConfiguration
    ) private view returns (JBBallotState) {
        // If there is no ballot funding cycle, the ballot is empty.
        if (_ballotFundingCycleConfiguration == 0) return JBBallotState.Empty;

        // Get the ballot funding cycle.
        JBRuleset memory _ballotFundingCycle = _getStructFor(
            _projectId,
            _ballotFundingCycleConfiguration
        );

        // If there is no ballot, it's considered empty.
        if (_ballotFundingCycle.ballot == IJBFundingCycleBallot(address(0)))
            return JBBallotState.Empty;

        // Return the ballot's state
        return
            _ballotFundingCycle.ballot.stateOf(
                _projectId,
                _rulesetId,
                _start
            );
    }

    /// @notice Unpack a funding cycle's packed stored values into an easy-to-work-with funding cycle struct.
    /// @param _projectId The ID of the project to which the funding cycle belongs.
    /// @param _rulesetId The funding cycle rulesetId to get the full struct for.
    /// @return ruleset A funding cycle struct.
    function _getStructFor(
        uint256 _projectId,
        uint256 _rulesetId
    ) private view returns (JBRuleset memory ruleset) {
        // Return an empty funding cycle if the rulesetId specified is 0.
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

        // ballot in bits 0-159 bits.
        ruleset.ballot = IJBFundingCycleBallot(
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
