// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./RLPReader.sol";

library RandaoLib {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.Iterator;
    using RLPReader for bytes;

    function getRandaoFromHeader(RLPReader.RLPItem memory item) pure internal returns (bytes32) {
        RLPReader.Iterator memory iterator = item.iterator();
        // mixDigest is at item 13 (0-base index)
        for (uint256 i = 0; i < 13; i++) {
            iterator.next();
        }

        return bytes32(iterator.next().toUint());
    }

    function verifyHeaderAndGetRandao(bytes32 headerHash, bytes memory headerRlpBytes) pure internal returns (bytes32) {
        RLPReader.RLPItem memory item = headerRlpBytes.toRlpItem();
        require(headerHash == item.rlpBytesKeccak256(), "header hash mismatch");
        return getRandaoFromHeader(item);
    }
}