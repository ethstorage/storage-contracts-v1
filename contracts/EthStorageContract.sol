// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StorageContract.sol";
import "./Decoder.sol";
import "./BinaryRelated.sol";

contract EthStorageContract is StorageContract, Decoder {
    event PutBlob(uint256 indexed kvIdx, uint256 indexed kvSize, bytes32 indexed dataHash);

    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury,
        uint256 _prepaidAmount
    ) payable StorageContract(_config, _startTime, _storageCost, _dcfFactor, _nonceLimit, _treasury, _prepaidAmount) {}

    function modExp(uint256 _b, uint256 _e, uint256 _m) internal view returns (uint256 result) {
        assembly {
            // Free memory pointer
            let pointer := mload(0x40)

            // Define length of base, exponent and modulus. 0x20 == 32 bytes
            mstore(pointer, 0x20)
            mstore(add(pointer, 0x20), 0x20)
            mstore(add(pointer, 0x40), 0x20)

            // Define variables base, exponent and modulus
            mstore(add(pointer, 0x60), _b)
            mstore(add(pointer, 0x80), _e)
            mstore(add(pointer, 0xa0), _m)

            // Call the precompiled contract 0x05 = bigModExp, reuse scratch to get the results
            if iszero(staticcall(not(0), 0x05, pointer, 0xc0, 0x0, 0x20)) {
                revert(0, 0)
            }

            result := mload(0x0)

            // Clear memory or exclude the memory
            mstore(0x40, add(pointer, 0xc0))
        }
    }

    function pointEvaluation(bytes memory input) internal view returns (uint256 versionedHash, uint256 x, uint256 y) {
        assembly {
            versionedHash := mload(add(input, 0x20))
            x := mload(add(input, 0x40))
            y := mload(add(input, 0x60))

            // Call the precompiled contract 0x14 = point evaluation, reuse scratch to get the results
            if iszero(staticcall(not(0), 0x14, add(input, 0x20), 0xc0, 0x0, 0x40)) {
                revert(0, 0)
            }

            // TODO: Check the results
        }
    }

    function decodeSample(
        Proof memory proof,
        uint256 encodingKey,
        uint256 sampleIdxInKv,
        uint256 mask
    ) public view returns (bool) {
        uint256 ruBn254 = 0x931d596de2fd10f01ddd073fd5a90a976f169c76f039bb91c4775720042d43a;
        uint256 modulusBn254 = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
        uint256 xBn254 = modExp(ruBn254, sampleIdxInKv, modulusBn254);

        uint256[] memory input = new uint256[](3);
        // TODO: simple hash to curve mapping
        input[0] = encodingKey % modulusBn254;
        input[1] = xBn254;
        input[2] = mask;
        return (verifyDecoding(input, proof) == 0);
    }

    function checkInclusive(
        bytes32 dataHash,
        uint256 sampleIdxInKv,
        uint256 decodedData,
        bytes memory peInput
    ) public view returns (bool) {
        uint256 ruBls = 0x564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d36306;
        uint256 modulusBls = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
        // peInput includes an input point that comes from bit reversed sampleIdxInKv
        uint256 sampleIdxInKvRev = BinaryRelated.reverseBits(12, sampleIdxInKv);
        uint256 xBls = modExp(ruBls, sampleIdxInKvRev, modulusBls);
        (uint256 versionedHash, uint256 evalX, uint256 evalY) = pointEvaluation(peInput);
        if (evalX != xBls || bytes24(bytes32(versionedHash)) != dataHash) {
            return false;
        }

        return evalY == decodedData;
    }

    /*
     * Decode the sample and check the decoded sample is included in the BLOB corresponding to on-chain datahashes.
     */
    function decodeAndCheckInclusive(
        uint256 kvIdx,
        uint256 sampleIdxInKv,
        address miner,
        bytes32 encodedData,
        bytes calldata proof
    ) public view virtual override returns (bool) {
        PhyAddr memory kvInfo = kvMap[idxMap[kvIdx]];
        (Proof memory decodeProof, uint256 mask, bytes memory peInput) = abi.decode(proof, (Proof, uint256, bytes));

        // BLOB decoding check
        if (
            !decodeSample(decodeProof, uint256(keccak256(abi.encode(kvInfo.hash, miner, kvIdx))), sampleIdxInKv, mask)
        ) {
            return false;
        }

        // Inclusive proof of decodedData = mask ^ encodedData
        return checkInclusive(kvInfo.hash, sampleIdxInKv, mask ^ uint256(encodedData), peInput);
    }

    // Write a large value to KV store.  If the KV pair exists, overrides it.  Otherwise, will append the KV to the KV array.
    function putBlob(bytes32 key, uint256 blobIdx, uint256 length) public payable virtual {
        bytes32 dataHash = bytes32(0);
        uint256 kvIdx = _putInternal(key, dataHash, length);

        emit PutBlob(kvIdx, length, dataHash);
    }
}
