// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract.sol";
import "./Decoder2.sol";


contract EthStorageContract2 is EthStorageContract, Decoder2 {

    function initialize(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury,
        uint256 _prepaidAmount
    ) public payable initializer {
        __init_eth_storage(_config, _startTime, _storageCost, _dcfFactor, _nonceLimit, _treasury, _prepaidAmount);
    }

    function decodeSample(
        uint256[] memory masks,
        bytes calldata decodeProof
    ) public view returns (bool) {
        (uint[2] memory pA, uint[2][2] memory pB, uint[2] memory pC) = abi.decode(decodeProof, (uint[2], uint[2][2], uint[2]));
        // verifyProof uses the opcode 'return', so if we call verifyProof directly, it will lead to a compiler warning about 'unreachable code' 
        // and causes the caller function return directly
        return this.verifyProof(pA, pB, pC, [masks[0], masks[1]]);
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
        require(decodeProof.length == 1, "decodeProof length mismatch");
        // calculate the number of samples range of the sample check
        uint256 rows = 1 << (shardEntryBits + sampleLenBits);

        for (uint256 i = 0; i < randomChecks; i++) {
            (uint256 kvIdx, uint256 sampleIdxInKv) = getSampleIdx(rows, startShardId, hash0);
            PhyAddr memory kvInfo = kvMap[idxMap[kvIdx]];

            require(
                checkInclusive(kvInfo.hash, sampleIdxInKv, masks[i] ^ uint256(encodedSamples[i]), inclusiveProofs[i]),
                "invalid samples"
            );
            hash0 = keccak256(abi.encode(hash0, encodedSamples[i]));
        }

        require(decodeSample(masks, decodeProof[0]), "decode failed");
        return hash0;
    }
}
