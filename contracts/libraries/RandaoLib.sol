// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./RLPReader.sol";

/// @title RandaoLib
/// @notice Handles Randao related operations
library RandaoLib {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.Iterator;
    using RLPReader for bytes;

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

    /// @notice Verify the header hash and get the Randao mixDigest
    /// @param _headerHash The hash of the header
    /// @param _headerRlpBytes The RLP data of the header
    /// @return The Randao mixDigest
    function verifyHeaderAndGetRandao(
        bytes32 _headerHash,
        bytes memory _headerRlpBytes
    ) internal pure returns (bytes32) {
        RLPReader.RLPItem memory item = _headerRlpBytes.toRlpItem();
        require(_headerHash == item.rlpBytesKeccak256(), "RandaoLib: header hash mismatch");
        return getRandaoFromHeader(item);
    }
}
