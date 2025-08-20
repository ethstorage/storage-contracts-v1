// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./RLPReader.sol";

/// @title RandaoLib
/// @notice Handles Randao related operations
library RandaoLib {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.Iterator;
    using RLPReader for bytes;

    /// @notice Thrown when the header hash does not match
    error RandaoLib_HeaderHashMismatch();

    /// @notice Get the Randao mixDigest from the header
    /// @param _item The RLP data of the header
    /// @return The Randao mixDigest
    function getRandaoFromHeader(RLPReader.RLPItem memory _item) internal pure returns (bytes32) {
        RLPReader.Iterator memory iterator = _item.iterator();
        // mixDigest is at item 13 (0-base index)
        for (uint256 i = 0; i < 13; i++) {
            iterator.next();
        }

        return bytes32(iterator.next().toUint());
    }

    /// @notice Get the timestamp from the header
    /// @param _headerRlpBytes The RLP data of the header
    /// @return The timestamp
    function getTimestampFromHeader(bytes memory _headerRlpBytes) internal pure returns (uint256) {
        RLPReader.RLPItem memory item = _headerRlpBytes.toRlpItem();
        RLPReader.Iterator memory iterator = item.iterator();
        // timestamp is at item 11 (0-base index)
        for (uint256 i = 0; i < 11; i++) {
            iterator.next();
        }

        return iterator.next().toUint();
    }

    /// @notice Verify the header hash and get the Randao mixDigest
    /// @param _headerHash The hash of the header
    /// @param _headerRlpBytes The RLP data of the header
    /// @return The Randao mixDigest
    function verifyHeaderAndGetRandao(bytes32 _headerHash, bytes memory _headerRlpBytes)
        internal
        pure
        returns (bytes32)
    {
        RLPReader.RLPItem memory item = _headerRlpBytes.toRlpItem();
        if (_headerHash != item.rlpBytesKeccak256()) {
            revert RandaoLib_HeaderHashMismatch();
        }
        return getRandaoFromHeader(item);
    }
}
