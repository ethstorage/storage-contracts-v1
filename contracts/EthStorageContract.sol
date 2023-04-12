// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StorageContract.sol";
import "./Decoder.sol";

contract EthStorageContract is StorageContract, Decoder {
    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury,
        uint256 _prepaidAmount
    ) payable StorageContract(_config, _startTime, _storageCost, _dcfFactor, _nonceLimit, _treasury, _prepaidAmount) {}

    /*
     * Decode the sample and check the decoded sample is included in the BLOB corresponding to on-chain datahashes.
     */
    function decodeAndCheckInclusive(
        uint256 sampleIdxInKV,
        PhyAddr memory kvInfo,
        address miner,
        bytes32 encodedData,
        bytes calldata inclusiveProof
    ) public virtual override returns (bool) {
        uint256 encodingKey = uint256(keccak256(abi.encode(kvInfo.hash, miner, sampleIdxInKV)));
        uint256 ru = 4158865282786404163413953114870269622875596290766033564087307867933865333818;
        uint256 prime = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
        uint256 x = modExp(ru, sampleIdxInKV, prime);
        uint256 mask = 0;
        Proof memory proof;
        (proof, mask) = abi.decode(inclusiveProof, (Proof, uint256));
        uint256[] memory input = new uint256[](3);
        input[0] = encodingKey;
        input[1] = x;
        input[2] = mask;
        if (verifyDecoding(input, proof) != 0) {
            return false;
        }
        // inclusive proof of decodedData = mask ^ encodedData
        return true;
    }

    function modExp(uint256 _b, uint256 _e, uint256 _m) internal returns (uint256 result) {
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

            // Store the result
            let value := mload(0xc0)

            // Call the precompiled contract 0x05 = bigModExp
            if iszero(call(not(0), 0x05, 0, pointer, 0xc0, value, 0x20)) {
                revert(0, 0)
            }

            result := mload(value)
        }
    }
}
