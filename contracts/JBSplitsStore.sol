// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {JBOperatable, Context} from "./abstract/JBOperatable.sol";
import {IJBDirectory} from "./interfaces/IJBDirectory.sol";
import {IJBOperatorStore} from "./interfaces/IJBOperatorStore.sol";
import {IJBProjects} from "./interfaces/IJBProjects.sol";
import {IJBSplitsStore} from "./interfaces/IJBSplitsStore.sol";
import {IJBSplitAllocator} from "./interfaces/IJBSplitAllocator.sol";
import {JBConstants} from "./libraries/JBConstants.sol";
import {JBOperations} from "./libraries/JBOperations.sol";
import {JBGroupedSplits} from "./structs/JBGroupedSplits.sol";
import {JBSplit} from "./structs/JBSplit.sol";

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

/// @notice Stores splits for each project.
contract JBSplitsStore is JBOperatable, ERC2771Context, IJBSplitsStore {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error INVALID_LOCKED_UNTIL();
    error INVALID_PROJECT_ID();
    error INVALID_SPLIT_PERCENT();
    error INVALID_TOTAL_PERCENT();
    error PREVIOUS_LOCKED_SPLITS_NOT_INCLUDED();

    //*********************************************************************//
    // --------------------- private stored properties ------------------- //
    //*********************************************************************//

    /// @notice The number of splits currently set for each project ID's configurations.
    /// @custom:param _projectId The ID of the project to get the split count for.
    /// @custom:param _domain An identifier within which the returned splits should be considered active.
    /// @custom:param _group The identifying group of the splits.
    mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256))) private _splitCountOf;

    /// @notice Packed data of splits for each project ID's configurations.
    /// @custom:param _projectId The ID of the project to get packed splits data for.
    /// @custom:param _domain An identifier within which the returned splits should be considered active.
    /// @custom:param _group The identifying group of the splits.
    /// @custom:param _index The indexed order that the split was set at.
    mapping(uint256 => mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256)))) private
        _packedSplitParts1Of;

    /// @notice More packed data of splits for each project ID's configurations.
    /// @dev This packed data is often 0.
    /// @custom:param _projectId The ID of the project to get packed splits data for.
    /// @custom:param _domain An identifier within which the returned splits should be considered active.
    /// @custom:param _group The identifying group of the splits.
    /// @custom:param _index The indexed order that the split was set at.
    mapping(uint256 => mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256)))) private
        _packedSplitParts2Of;

    //*********************************************************************//
    // ---------------- public immutable stored properties --------------- //
    //*********************************************************************//

    /// @notice Mints ERC-721's that represent project ownership and transfers.
    IJBProjects public immutable override projects;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public immutable override directory;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Get all splits for the specified project ID, within the specified domain, for the specified group.
    /// @param _projectId The ID of the project to get splits for.
    /// @param _domain An identifier within which the returned splits should be considered active.
    /// @param _group The identifying group of the splits.
    /// @return An array of all splits for the project.
    function splitsOf(uint256 _projectId, uint256 _domain, uint256 _group)
        external
        view
        override
        returns (JBSplit[] memory)
    {
        return _getStructsFor(_projectId, _domain, _group);
    }

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param _operatorStore A contract storing operator assignments.
    /// @param _projects A contract which mints ERC-721's that represent project ownership and transfers.
    /// @param _directory A contract storing directories of terminals and controllers for each project.
    constructor(IJBOperatorStore _operatorStore, IJBProjects _projects, IJBDirectory _directory, address _trustedForwarder)
        JBOperatable(_operatorStore)
        ERC2771Context(_trustedForwarder)
    {
        projects = _projects;
        directory = _directory;
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Sets a project's splits.
    /// @dev Only the owner or operator of a project, or the current controller contract of the project, can set its splits.
    /// @dev The new splits must include any currently set splits that are locked.
    /// @param _projectId The ID of the project for which splits are being added.
    /// @param _domain An identifier within which the splits should be considered active.
    /// @param _groupedSplits An array of splits to set for any number of groups.
    function set(uint256 _projectId, uint256 _domain, JBGroupedSplits[] calldata _groupedSplits)
        external
        override
        requirePermissionAllowingOverride(
            projects.ownerOf(_projectId),
            _projectId,
            JBOperations.SET_SPLITS,
            address(directory.controllerOf(_projectId)) ==  _msgSender()
        )
    {
        // Keep a reference to the number of grouped splits.
        uint256 _numberOfGroupedSplits = _groupedSplits.length;

        // Set each grouped splits.
        for (uint256 _i; _i < _numberOfGroupedSplits;) {
            // Get a reference to the grouped split being iterated on.
            JBGroupedSplits memory _groupedSplit = _groupedSplits[_i];

            // Set the splits for the group.
            _set(_projectId, _domain, _groupedSplit.group, _groupedSplit.splits);

            unchecked {
                ++_i;
            }
        }
    }

    //*********************************************************************//
    // --------------------- private helper functions -------------------- //
    //*********************************************************************//

    /// @notice Sets a project's splits.
    /// @dev The new splits must include any currently set splits that are locked.
    /// @param _projectId The ID of the project for which splits are being added.
    /// @param _domain An identifier within which the splits should be considered active.
    /// @param _group An identifier between of splits being set. All splits within this _group must add up to within 100%.
    /// @param _splits The splits to set.
    function _set(uint256 _projectId, uint256 _domain, uint256 _group, JBSplit[] memory _splits)
        internal
    {
        // Get a reference to the project's current splits.
        JBSplit[] memory _currentSplits = _getStructsFor(_projectId, _domain, _group);

        // Keep a reference to the number of splits.
        uint256 _numberOfCurrentSplits = _currentSplits.length;

        // Check to see if all locked splits are included.
        for (uint256 _i; _i < _numberOfCurrentSplits;) {
            // If not locked, continue.
            if (
                block.timestamp < _currentSplits[_i].lockedUntil
                    && !_includesLocked(_splits, _currentSplits[_i])
            ) revert PREVIOUS_LOCKED_SPLITS_NOT_INCLUDED();

            unchecked {
                ++_i;
            }
        }

        // Add up all the percents to make sure they cumulatively are under 100%.
        uint256 _percentTotal;

        // Keep a reference to the number of splits.
        uint256 _numberOfSplits = _splits.length;

        for (uint256 _i; _i < _numberOfSplits;) {
            // The percent should be greater than 0.
            if (_splits[_i].percent == 0) revert INVALID_SPLIT_PERCENT();

            // ProjectId should be within a uint56
            if (_splits[_i].projectId > type(uint56).max) revert INVALID_PROJECT_ID();

            // Add to the total percents.
            _percentTotal = _percentTotal + _splits[_i].percent;

            // Validate the total does not exceed the expected value.
            if (_percentTotal > JBConstants.SPLITS_TOTAL_PERCENT) revert INVALID_TOTAL_PERCENT();

            uint256 _packedSplitParts1;

            // prefer add to balance in bit 0.
            if (_splits[_i].preferAddToBalance) _packedSplitParts1 = 1;
            // percent in bits 1-32.
            _packedSplitParts1 |= _splits[_i].percent << 1;
            // projectId in bits 33-88.
            _packedSplitParts1 |= _splits[_i].projectId << 33;
            // beneficiary in bits 89-248.
            _packedSplitParts1 |= uint256(uint160(address(_splits[_i].beneficiary))) << 89;

            // Store the first split part.
            _packedSplitParts1Of[_projectId][_domain][_group][_i] = _packedSplitParts1;

            // If there's data to store in the second packed split part, pack and store.
            if (
                _splits[_i].lockedUntil > 0
                    || _splits[_i].allocator != IJBSplitAllocator(address(0))
            ) {
                // Locked until should be within a uint48
                if (_splits[_i].lockedUntil > type(uint48).max) revert INVALID_LOCKED_UNTIL();

                // lockedUntil in bits 0-47.
                uint256 _packedSplitParts2 = uint48(_splits[_i].lockedUntil);
                // allocator in bits 48-207.
                _packedSplitParts2 |= uint256(uint160(address(_splits[_i].allocator))) << 48;

                // Store the second split part.
                _packedSplitParts2Of[_projectId][_domain][_group][_i] = _packedSplitParts2;

                // Otherwise if there's a value stored in the indexed position, delete it.
            } else if (_packedSplitParts2Of[_projectId][_domain][_group][_i] > 0) {
                delete _packedSplitParts2Of[_projectId][_domain][_group][_i];
            }

            emit SetSplit(_projectId, _domain, _group, _splits[_i],  _msgSender());

            unchecked {
                ++_i;
            }
        }

        // Set the new length of the splits.
        _splitCountOf[_projectId][_domain][_group] = _numberOfSplits;
    }

    /// @notice A flag indiciating if the provided splits array includes the locked split.
    /// @param _splits The array of splits to check within.
    /// @param _lockedSplit The locked split.
    /// @return A flag indicating if the `_lockedSplit` is contained in the `_splits`.
    function _includesLocked(JBSplit[] memory _splits, JBSplit memory _lockedSplit)
        private
        pure
        returns (bool)
    {
        // Keep a reference to the number of splits.
        uint256 _numberOfSplits = _splits.length;

        for (uint256 _i; _i < _numberOfSplits;) {
            // Check for sameness.
            if (
                _splits[_i].percent == _lockedSplit.percent
                    && _splits[_i].beneficiary == _lockedSplit.beneficiary
                    && _splits[_i].allocator == _lockedSplit.allocator
                    && _splits[_i].projectId == _lockedSplit.projectId
                    && _splits[_i].preferAddToBalance == _lockedSplit.preferAddToBalance
                // Allow lock extention.
                && _splits[_i].lockedUntil >= _lockedSplit.lockedUntil
            ) return true;

            unchecked {
                ++_i;
            }
        }

        return false;
    }

    /// @notice Unpack splits' packed stored values into easy-to-work-with split structs.
    /// @param _projectId The ID of the project to which the split belongs.
    /// @param _domain The identifier within which the returned splits should be considered active.
    /// @param _group The identifying group of the splits.
    /// @return splits The split structs.
    function _getStructsFor(uint256 _projectId, uint256 _domain, uint256 _group)
        private
        view
        returns (JBSplit[] memory)
    {
        // Get a reference to the number of splits that need to be added to the returned array.
        uint256 _splitCount = _splitCountOf[_projectId][_domain][_group];

        // Initialize an array to be returned that has the set length.
        JBSplit[] memory _splits = new JBSplit[](_splitCount);

        // Loop through each split and unpack the values into structs.
        for (uint256 _i; _i < _splitCount;) {
            // Get a reference to the fist packed data.
            uint256 _packedSplitPart1 = _packedSplitParts1Of[_projectId][_domain][_group][_i];

            // Populate the split struct.
            JBSplit memory _split;

            // prefer add to balance in bit 0.
            _split.preferAddToBalance = _packedSplitPart1 & 1 == 1;
            // percent in bits 1-32.
            _split.percent = uint256(uint32(_packedSplitPart1 >> 1));
            // projectId in bits 33-88.
            _split.projectId = uint256(uint56(_packedSplitPart1 >> 33));
            // beneficiary in bits 89-248.
            _split.beneficiary = payable(address(uint160(_packedSplitPart1 >> 89)));

            // Get a reference to the second packed data.
            uint256 _packedSplitPart2 = _packedSplitParts2Of[_projectId][_domain][_group][_i];

            // If there's anything in it, unpack.
            if (_packedSplitPart2 > 0) {
                // lockedUntil in bits 0-47.
                _split.lockedUntil = uint256(uint48(_packedSplitPart2));
                // allocator in bits 48-207.
                _split.allocator = IJBSplitAllocator(address(uint160(_packedSplitPart2 >> 48)));
            }

            // Add the split to the value being returned.
            _splits[_i] = _split;

            unchecked {
                ++_i;
            }
        }

        return _splits;
    }

    /// @notice Returns the sender, prefered to use over `msg.sender`
    /// @return _sender the sender address of this call.
    function _msgSender() internal view override(ERC2771Context, Context) returns (address _sender) {
        return ERC2771Context._msgSender();
    }

    /// @notice Returns the calldata, prefered to use over `msg.data`
    /// @return _calldata the `msg.data` of this call
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata _calldata) {
        return ERC2771Context._msgData();
    }
}
