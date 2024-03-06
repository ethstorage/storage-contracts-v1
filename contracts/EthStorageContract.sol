// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StorageContract.sol";
import "./Decoder.sol";
import "./BinaryRelated.sol";

contract EthStorageContract is StorageContract, Decoder {
    uint256 constant modulusBls = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant ruBls = 0x564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d36306;
    uint256 constant ruBn254 = 0x931d596de2fd10f01ddd073fd5a90a976f169c76f039bb91c4775720042d43a;
    uint256 constant modulusBn254 = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    uint256 constant fieldElementsPerBlob = 0x1000;

    event PutBlob(uint256 indexed kvIdx, uint256 indexed kvSize, bytes32 indexed dataHash);

    function initialize(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury,
        uint256 _prepaidAmount,
        address _owner
    ) public payable initializer {
        __init_storage(_config, _startTime, _storageCost, _dcfFactor, _nonceLimit, _treasury, _prepaidAmount, _owner);
    }

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

            // Call the precompiled contract 0x0a = point evaluation, reuse scratch to get the results
            if iszero(staticcall(not(0), 0x0a, add(input, 0x20), 0xc0, 0x0, 0x40)) {
                revert(0, 0)
            }
            // Check the results
            if iszero(eq(mload(0x0), fieldElementsPerBlob)) {
                revert(0, 0)
            }
            if iszero(eq(mload(0x20), modulusBls)) {
                revert(0, 0)
            }
        }
    }

    function decodeSample(
        Proof memory proof,
        uint256 encodingKey,
        uint256 sampleIdxInKv,
        uint256 mask
    ) public view returns (bool) {
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
        if (dataHash == 0x0) {
            return decodedData == 0;
        }
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
        uint256 mask,
        bytes calldata inclusiveProof,
        bytes calldata decodeProof
    ) public view virtual returns (bool) {
        PhyAddr memory kvInfo = kvMap[idxMap[kvIdx]];
        Proof memory proof = abi.decode(decodeProof, (Proof));
        // BLOB decoding check
        if (
            !decodeSample(proof, uint256(keccak256(abi.encode(kvInfo.hash, miner, kvIdx))), sampleIdxInKv, mask)
        ) {
            return false;
        }

        // Inclusive proof of decodedData = mask ^ encodedData
        return checkInclusive(kvInfo.hash, sampleIdxInKv, mask ^ uint256(encodedData), inclusiveProof);
    }

    function getSampleIdx(
        uint256 rows,
        uint256 startShardId,
        bytes32 hash0
    ) public view returns (uint256, uint256) {
        uint256 parent = uint256(hash0) % rows;
        uint256 sampleIdx = parent + (startShardId << (shardEntryBits + sampleLenBits));
        uint256 kvIdx = sampleIdx >> sampleLenBits;
        uint256 sampleIdxInKv = sampleIdx % (1 << sampleLenBits);
        return (kvIdx, sampleIdxInKv);
    }

    function verifySamples(
        uint256 startShardId,
        bytes32 hash0,
        address miner,
        bytes32[] memory encodedSamples,
        uint256[] memory masks,
        bytes[] calldata inclusiveProofs,
        bytes[] calldata decodeProof
    ) public view virtual override returns (bytes32) {
        require(encodedSamples.length == randomChecks, "data length mismatch");
        require(masks.length == randomChecks, "masks length mismatch");
        require(inclusiveProofs.length == randomChecks, "proof length mismatch");
        require(decodeProof.length == randomChecks, "decodeProof length mismatch");

        // calculate the number of samples range of the sample check
        uint256 rows = 1 << (shardEntryBits + sampleLenBits);

        for (uint256 i = 0; i < randomChecks; i++) {
            (uint256 kvIdx, uint256 sampleIdxInKv) = getSampleIdx(rows, startShardId, hash0);

            require(
                decodeAndCheckInclusive(kvIdx, sampleIdxInKv, miner, encodedSamples[i], masks[i], inclusiveProofs[i], decodeProof[i]),
                "invalid samples"
            );
            hash0 = keccak256(abi.encode(hash0, encodedSamples[i]));
        }
        return hash0;
    }    

    // Write a large value to KV store.  If the KV pair exists, overrides it.  Otherwise, will append the KV to the KV array.
    function putBlob(bytes32 key, uint256 blobIdx, uint256 length) public payable virtual {
        bytes32 dataHash = blobhash(blobIdx);
        require(dataHash != 0, "failed to get blob hash");
        uint256 kvIdx = _putInternal(key, dataHash, length);

        emit PutBlob(kvIdx, length, dataHash);
    }
}
