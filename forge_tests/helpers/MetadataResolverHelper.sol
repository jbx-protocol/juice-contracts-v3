// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {JBMetadataResolver} from "@juicebox/libraries/JBMetadataResolver.sol";

/**
 * @notice Contract to create Juicebox pay/redeem hook metadata
 *
 * @dev    Metadata are built as:
 *         - 32B of reserved space for the protocol
 *         - a lookup table `hookId: offset`, defining the offset of the metadata for each hook.
 *           The offset fits 1 bytes, the ID 4 bytes. This table is padded to 32B.
 *         - the metadata for each hook, padded to 32B each
 *
 *            +-----------------------+ offset: 0
 *            | 32B reserved          |
 *            +-----------------------+ offset: 1 = end of first 32B
 *            | (hook1 ID,offset1)    |
 *            | (hook2 ID,offset2)    |
 *            | 0's padding           |
 *            +-----------------------+ offset: offset1 = 1 + number of words taken by the padded table
 *            | hook 1 metadata1      |
 *            | 0's padding           |
 *            +-----------------------+ offset: offset2 = offset1 + number of words taken by the metadata1
 *            | hook 2 metadata2      |
 *            | 0's padding           |
 *            +-----------------------+
 *
 *         This contract is intended to expose the library functions as a helper for frontends.
 */
contract MetadataResolverHelper {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error LENGTH_MISMATCH();
    error METADATA_TOO_LONG();

    /**
     * @notice Parse the metadata to find the metadata for a specific hook
     *
     * @dev    Returns false and an empty bytes if no metadata is found
     *
     * @param  _id             The hook id to find
     * @param  _metadata       The metadata to parse
     *
     * @return _found          Whether the metadata was found
     * @return _targetMetadata The metadata for the hook
     */
    function getHookMetadata(bytes4 _id, bytes calldata _metadata)
        public
        pure
        returns (bool _found, bytes memory _targetMetadata)
    {
        return JBMetadataResolver.getHookMetadata(_id, _metadata);
    }

    /**
     * @notice Create the metadata for a list of hooks
     *
     * @dev    Intended for offchain use
     *
     * @param _ids             The list of hook ids
     * @param _metadatas       The list of metadatas
     *
     * @return _metadata       The packed metadata for the hooks
     */
    function createHooksMetadata(bytes4[] calldata _ids, bytes[] calldata _metadatas)
        public
        pure
        returns (bytes memory _metadata)
    {
        if (_ids.length != _metadatas.length) revert LENGTH_MISMATCH();

        // Add a first empty 32B for the protocol reserved word
        _metadata = abi.encodePacked(bytes32(0));

        // First offset for the data is after the first reserved word...
        uint256 _offset = 1;

        // ... and after the id/offset lookup table, rounding up to 32 bytes words if not a multiple
        _offset += ((_ids.length * JBMetadataResolver.TOTAL_ID_SIZE) - 1)
            / JBMetadataResolver.WORD_SIZE + 1;

        // For each id, add it to the lookup table with the next free offset, then increment the offset by the data length (rounded up)
        for (uint256 _i; _i < _ids.length;) {
            _metadata = abi.encodePacked(_metadata, _ids[_i], bytes1(uint8(_offset)));
            _offset += _metadatas[_i].length / JBMetadataResolver.WORD_SIZE;

            // Overflowing a bytes1?
            if (_offset > 2 ** 8) revert METADATA_TOO_LONG();
            unchecked {
                ++_i;
            }
        }

        // Pad the table to a multiple of 32B
        uint256 _paddedLength = _metadata.length % JBMetadataResolver.WORD_SIZE == 0
            ? _metadata.length
            : (_metadata.length / JBMetadataResolver.WORD_SIZE + 1) * JBMetadataResolver.WORD_SIZE;
        assembly {
            mstore(_metadata, _paddedLength)
        }

        // Add each metadata to the array, each padded to 32 bytes
        for (uint256 _i; _i < _metadatas.length; _i++) {
            _metadata = abi.encodePacked(_metadata, _metadatas[_i]);
            _paddedLength = _metadata.length % JBMetadataResolver.WORD_SIZE == 0
                ? _metadata.length
                : (_metadata.length / JBMetadataResolver.WORD_SIZE + 1) * JBMetadataResolver.WORD_SIZE;

            assembly {
                mstore(_metadata, _paddedLength)
            }
        }
    }

    /**
     * @notice Add a hook to an existing metadata
     *
     * @param _idToAdd         The id of the hook to add
     * @param _dataToAdd       The metadata of the hook to add
     * @param _originalMetadata The original metadata
     *
     * @return _newMetadata    The new metadata with the hook added
     */
    function addHookToMetadata(
        bytes4 _idToAdd,
        bytes calldata _dataToAdd,
        bytes calldata _originalMetadata
    ) public pure returns (bytes memory _newMetadata) {
        return JBMetadataResolver.addToMetadata(_idToAdd, _dataToAdd, _originalMetadata);
    }
}
