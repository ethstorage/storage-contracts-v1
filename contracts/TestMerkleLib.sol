// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MerkleLib.sol";

contract TestMerkleLib {
    function merkleRoot(bytes memory data, uint256 chunkSize, uint256 nChunkBits) public pure returns (bytes32) {
        return MerkleLib.merkleRoot(data, chunkSize, nChunkBits);
    }

    function merkleRootMinTree(bytes memory data, uint256 chunkSize) public pure returns (bytes32) {
        return MerkleLib.merkleRootWithMinTree(data, chunkSize);
    }

    function merkleRootNoView(bytes memory data, uint256 chunkSize, uint256 nChunkBits) public returns (bytes32) {
        return MerkleLib.merkleRoot(data, chunkSize, nChunkBits);
    }

    function keccak256NoView(bytes memory data) public returns (bytes32) {
        return keccak256(data);
    }

    function verify(
        bytes memory chunkData,
        uint256 chunkIdx,
        bytes32 root,
        bytes32[] memory proofs
    ) public pure returns (bool) {
        return MerkleLib.verify(keccak256(chunkData), chunkIdx, root, proofs);
    }

    function getProof(
        bytes memory data,
        uint256 chunkSize,
        uint256 nChunkBits,
        uint256 chunkIdx
    ) public pure returns (bytes32[] memory) {
        return MerkleLib.getProof(data, chunkSize, nChunkBits, chunkIdx);
    }

    function getMaxLeafsNum(uint256 kvSize, uint256 chunkSize) public pure returns (uint256) {
        return MerkleLib.getMaxLeafsNum(kvSize, chunkSize);
    }
}
