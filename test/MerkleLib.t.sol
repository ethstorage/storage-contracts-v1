// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {MerkleLib} from "../contracts/libraries/MerkleLib.sol";

contract MerkleLibTest is Test {
    function testFullZeroDataVerify() public pure {
        uint256 chunkSize = 64;
        uint256 nChunkBits = 3;
        bytes memory data = new bytes(chunkSize * (1 << nChunkBits));

        _assertProofs(data, chunkSize, nChunkBits);
    }

    function testFullPseudoRandomDataVerify() public pure {
        uint256 chunkSize = 64;
        uint256 nChunkBits = 3;
        bytes memory data = _randomBytes(chunkSize * (1 << nChunkBits), bytes32("full-random"));

        _assertProofs(data, chunkSize, nChunkBits);
    }

    function testEightKilobyteData() public pure {
        uint256 chunkSize = 4096;
        uint256 nChunkBits = 1; // 2 chunks
        bytes memory data = _randomBytes(chunkSize * 2, bytes32("8k-data"));

        bytes32 root = MerkleLib.merkleRoot(data, chunkSize, nChunkBits);

        bytes memory leftChunk = _slice(data, 0, chunkSize);
        bytes32[] memory leftProof = MerkleLib.getProof(data, chunkSize, nChunkBits, 0);
        assertTrue(MerkleLib.verify(keccak256(leftChunk), 0, root, leftProof));

        bytes memory rightChunk = _slice(data, chunkSize, chunkSize);
        bytes32[] memory rightProof = MerkleLib.getProof(data, chunkSize, nChunkBits, 1);
        assertTrue(MerkleLib.verify(keccak256(rightChunk), 1, root, rightProof));
    }

    function testPartialRandomDataVerify0() public pure {
        bytes memory data = _randomBytes(8, bytes32("partial-0"));
        _assertProofs(data, 64, 3);
    }

    function testPartialRandomDataVerify1() public pure {
        bytes memory data = _randomBytes(64 * 3 + 16, bytes32("partial-1"));
        _assertProofs(data, 64, 3);
    }

    function testPartialRandomDataVerify2() public pure {
        bytes memory data = _randomBytes(64 * 6 + 48, bytes32("partial-2"));
        _assertProofs(data, 64, 3);
    }

    function testGasForLargeChunks() public view {
        uint256 chunkSize = 4096;
        uint256 nChunkBits = 3;

        bytes memory data1 = _randomBytes(chunkSize, bytes32("gas-1"));
        bytes memory data2 = _randomBytes(chunkSize * 2, bytes32("gas-2"));
        bytes memory data3 = _randomBytes(chunkSize * 3, bytes32("gas-3"));

        uint256 g1 = gasleft();
        MerkleLib.merkleRoot(data1, chunkSize, nChunkBits);
        uint256 used1 = g1 - gasleft();

        uint256 g2 = gasleft();
        MerkleLib.merkleRoot(data2, chunkSize, nChunkBits);
        uint256 used2 = g2 - gasleft();

        uint256 g3 = gasleft();
        MerkleLib.merkleRoot(data3, chunkSize, nChunkBits);
        uint256 used3 = g3 - gasleft();

        console2.log("gas merkleRoot (1 chunk):", used1);
        console2.log("gas merkleRoot (2 chunks):", used2);
        console2.log("gas merkleRoot (3 chunks):", used3);
    }

    function testShouldForbidIllegalParameter() public {
        uint256 chunkSize = 64;
        uint256 nChunkBits = 3;
        bytes memory data = _randomBytes(chunkSize * 6 + 48, bytes32("illegal"));

        bytes32 root = MerkleLib.merkleRoot(data, chunkSize, nChunkBits);

        vm.expectRevert("index out of scope");
        this.callGetProof(data, chunkSize, nChunkBits, 10);

        bytes memory chunk = _slice(data, 0, chunkSize);
        bytes32[] memory proof = MerkleLib.getProof(data, chunkSize, nChunkBits, 0);
        assertTrue(MerkleLib.verify(keccak256(chunk), 0, root, proof));

        vm.expectRevert("chunkId overflows");
        this.callVerify(8, root, proof, keccak256(chunk));

        vm.expectRevert("chunkId overflows");
        this.callVerify(10, root, proof, keccak256(chunk));
    }

    function testGetMaxLeafsNum() public pure {
        assertEq(MerkleLib.getMaxLeafsNum(8192, 2048), 4);
        assertEq(MerkleLib.getMaxLeafsNum(4096, 2048), 2);
        assertEq(MerkleLib.getMaxLeafsNum(6000, 2048), 4);
        assertEq(MerkleLib.getMaxLeafsNum(3000, 2048), 2);
        assertEq(MerkleLib.getMaxLeafsNum(12288, 2048), 8);
    }

    function _assertProofs(bytes memory data, uint256 chunkSize, uint256 nChunkBits) internal pure {
        bytes32 root = MerkleLib.merkleRoot(data, chunkSize, nChunkBits);
        uint256 chunkCount = data.length == 0 ? 0 : (data.length + chunkSize - 1) / chunkSize;
        if (chunkCount == 0 && data.length != 0) {
            chunkCount = 1;
        }
        for (uint256 i = 0; i < chunkCount; i++) {
            uint256 start = i * chunkSize;
            uint256 remaining = data.length - start;
            uint256 len = remaining >= chunkSize ? chunkSize : remaining;
            bytes memory chunk = _slice(data, start, len);
            bytes32[] memory proof = MerkleLib.getProof(data, chunkSize, nChunkBits, i);
            assertTrue(MerkleLib.verify(keccak256(chunk), i, root, proof));
        }
    }

    function callVerify(uint256 chunkIdx, bytes32 root, bytes32[] calldata proofs, bytes32 chunkHash)
        external
        pure
        returns (bool)
    {
        return MerkleLib.verify(chunkHash, chunkIdx, root, proofs);
    }

    function callGetProof(bytes calldata data, uint256 chunkSize, uint256 nChunkBits, uint256 chunkIdx)
        external
        pure
        returns (bytes32[] memory)
    {
        return MerkleLib.getProof(data, chunkSize, nChunkBits, chunkIdx);
    }

    function _randomBytes(uint256 length, bytes32 seed) internal pure returns (bytes memory data) {
        data = new bytes(length);
        if (length == 0) {
            return data;
        }
        uint256 word;
        for (uint256 i = 0; i < length; i++) {
            if (i % 32 == 0) {
                word = uint256(keccak256(abi.encode(seed, i / 32)));
            }
            uint256 shift = 31 - (i % 32);
            data[i] = bytes1(uint8(word >> (shift * 8)));
        }
    }

    function _slice(bytes memory data, uint256 start, uint256 len) internal pure returns (bytes memory result) {
        if (len == 0) {
            return new bytes(0);
        }
        result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = data[start + i];
        }
    }
}
