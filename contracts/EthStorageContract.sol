// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StorageContract.sol";
import "./Decoder.sol";
import "./BinaryRelated.sol";

contract BlobHashGetterFactory {
    constructor() payable {
        bytes memory code = hex"6000354960005260206000F3";
        uint256 size = code.length;
        assembly {
            return(add(code, 0x020), size)
        }
    }
}

// TODO: remove the library if solidity has direct support the new opcode
library BlobHashGetter {
    function getBlobHash(address getter, uint256 idx) internal view returns (bytes32) {
        bool success;
        bytes32 blobHash;
        assembly {
            mstore(0x0, idx)
            success := staticcall(gas(), getter, 0x0, 0x20, 0x0, 0x20)
            blobHash := mload(0x0)
        }
        require(success, "failed to get blob hash");
        return blobHash;
    }
}

contract EthStorageContract is StorageContract, Decoder {
    uint256 constant modulusBls = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;
    uint256 constant ruBls = 0x564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d36306;
    uint256 constant ruBn254 = 0x931d596de2fd10f01ddd073fd5a90a976f169c76f039bb91c4775720042d43a;
    uint256 constant modulusBn254 = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    uint256 constant fieldElementsPerBlob = 0x1000;

    address public hashGetter;

    event PutBlob(uint256 indexed kvIdx, uint256 indexed kvSize, bytes32 indexed dataHash);

    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury,
        uint256 _prepaidAmount
    ) payable StorageContract(_config, _startTime, _storageCost, _dcfFactor, _nonceLimit, _treasury, _prepaidAmount) {
        hashGetter = address(new BlobHashGetterFactory());
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
        uint256[] memory masks,
        bytes calldata decodeProof
    ) public view virtual override returns (bool) {        
        require(masks.length == 2, "invalid mask length");
        uint256[2] memory publicSignals;
        for (uint i = 0; i < publicSignals.length; i++) {
            publicSignals[i] = masks[i];
        }

        (uint[2] memory pA, uint[2][2] memory pB, uint[2] memory pC) = abi.decode(decodeProof, (uint[2], uint[2][2], uint[2]));
        
        return verifyProof(pA, pB, pC, publicSignals);
    }

    function _checkInclusive(
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
    function checkInclusive(
        uint256 kvIdx,
        uint256 sampleIdxInKv,
        bytes32 encodedData,
        bytes calldata proof
    ) public view virtual override returns (bool, uint256) {
        PhyAddr memory kvInfo = kvMap[idxMap[kvIdx]];
        (uint256 mask, bytes memory peInput) = abi.decode(proof, (uint256, bytes));

        // Inclusive proof of decodedData = mask ^ encodedData
        return (_checkInclusive(kvInfo.hash, sampleIdxInKv, mask ^ uint256(encodedData), peInput), mask);
    }

    // Write a large value to KV store.  If the KV pair exists, overrides it.  Otherwise, will append the KV to the KV array.
    function putBlob(bytes32 key, uint256 blobIdx, uint256 length) public payable virtual {
        bytes32 dataHash = BlobHashGetter.getBlobHash(hashGetter, blobIdx);
        uint256 kvIdx = _putInternal(key, dataHash, length);

        emit PutBlob(kvIdx, length, dataHash);
    }
}
