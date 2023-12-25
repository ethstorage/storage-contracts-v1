// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./EthStorageContract.sol";
import "./MerkleLib.sol";

contract TestEthStorageContract is EthStorageContract {
    uint256 public currentTimestamp;

    struct MerkleProof {
        bytes32 data;
        bytes32 rootHash;
        bytes32[] proofs;
    }

    function setTimestamp(uint256 ts) public {
        require(ts > currentTimestamp, "ts");
        currentTimestamp = ts;
    }

    function put(bytes32 key, bytes memory data) public payable {
        bytes32 dataHash = MerkleLib.merkleRootWithMinTree(data, 32); // TODO: 64-bytes should be more efficient.
        _putInternal(key, dataHash, data.length);
    }

    function getEncodingKey(uint256 kvIdx, address miner) public view returns (bytes32) {
        return keccak256(abi.encode(kvMap[idxMap[kvIdx]].hash, miner, kvIdx));
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
        (Proof memory decodeProof, uint256 mask, MerkleProof memory mProof) = abi.decode(
            proof,
            (Proof, uint256, MerkleProof)
        );

        // BLOB decoding check
        if (
            !decodeSample(decodeProof, uint256(keccak256(abi.encode(kvInfo.hash, miner, kvIdx))), sampleIdxInKv, mask)
        ) {
            return false;
        }

        // Inclusive proof of decodedData = mask ^ encodedData
        if (!MerkleLib.verify(keccak256(abi.encode(mProof.data)), sampleIdxInKv, mProof.rootHash, mProof.proofs)) {
            return false;
        }

        uint256 expectedEncodedData = uint256(mProof.data) ^ mask;
        return bytes32(expectedEncodedData) == encodedData;
    }

    function verifySamples(
        uint256 startShardId,
        bytes32 hash0,
        address miner,
        bytes32[] memory encodedSamples,
        bytes[] calldata inclusiveProofs
    ) public view returns (bytes32) {
        return _verifySamples(startShardId, hash0, miner, encodedSamples, inclusiveProofs);
    }

    function getSampleIdx(uint256 startShardId, bytes32 hash0) public view returns (uint256, uint256, uint256) {
        // calculate the number of samples range of the sample check
        uint256 rows = 1 << (shardEntryBits + sampleLenBits); // kvNumbersPerShard * smapleNumersPerKV

        uint256 parent = uint256(hash0) % rows;
        uint256 sampleIdx = parent + (startShardId << (shardEntryBits + sampleLenBits));
        uint256 kvIdx = sampleIdx >> sampleLenBits;
        uint256 sampleIdxInKv = sampleIdx % (1 << sampleLenBits);

        return (sampleIdx, kvIdx, sampleIdxInKv);
    }

    function getNextHash0(bytes32 hash0, bytes32 encodedSample) public pure returns (bytes32) {
        hash0 = keccak256(abi.encode(hash0, encodedSample));
        return hash0;
    }

    function getBlockHash(uint256 blockNumber) public view returns (bytes32) {
        bytes32 bh = blockhash(blockNumber);
        return bh;
    }

    function getInitHash0(uint256 blockNumber, address miner, uint256 nonce) public view returns (bytes32) {
        bytes32 bh = getBlockHash(blockNumber);
        bytes32 hash0 = keccak256(abi.encode(miner, bh, nonce));
        return hash0;
    }

    function _mineWithoutDiffCompare(
        uint256 blockNumber,
        uint256 shardId,
        address miner,
        uint256 nonce,
        bytes32[] memory encodedSamples,
        bytes[] calldata proofs
    ) internal {
        // Obtain the blockhash of the block number of recent blocks
        require(block.number - blockNumber <= 64, "block number too old");
        bytes32 bh = blockhash(blockNumber);
        require(bh != bytes32(0), "failed to obtain blockhash");
        // Estimate block timestamp
        uint256 mineTs = block.timestamp - (block.number - blockNumber) * 12;

        // Given a blockhash and a miner, we only allow sampling up to nonce limit times.
        require(nonce < nonceLimit, "nonce too big");

        // Check if the data matches the hash in metadata and obtain the solution hash.
        bytes32 hash0 = keccak256(abi.encode(miner, bh, nonce));
        hash0 = _verifySamples(shardId, hash0, miner, encodedSamples, proofs);

        uint256 diff = _calculateDiffAndInitHashSingleShard(shardId, mineTs);

        _rewardMiner(shardId, miner, mineTs, diff);
    }

    function mine(
        uint256 blockNumber,
        uint256 shardId,
        address miner,
        uint256 nonce,
        bytes32[] memory encodedSamples,
        bytes[] calldata proofs
    ) public virtual override {
        return _mineWithoutDiffCompare(blockNumber, shardId, miner, nonce, encodedSamples, proofs);
    }

    function _mineWithFixedHash0(
        bytes32 initHash0,
        uint256 shardId,
        address miner,
        uint256 nonce,
        bytes32[] memory encodedSamples,
        bytes[] calldata proofs
    ) internal {
        // Obtain the blockhash of the block number of recent blocks
        uint256 mineTs = block.timestamp;

        // Given a blockhash and a miner, we only allow sampling up to nonce limit times.
        require(nonce < nonceLimit, "nonce too big");

        // Check if the data matches the hash in metadata and obtain the solution hash.
        bytes32 hash0 = _verifySamples(shardId, initHash0, miner, encodedSamples, proofs);

        uint256 diff = _calculateDiffAndInitHashSingleShard(shardId, mineTs);

        _rewardMiner(shardId, miner, mineTs, diff);
    }

    function mineWithFixedHash0(
        bytes32 initHash0,
        uint256 shardId,
        address miner,
        uint256 nonce,
        bytes32[] memory encodedSamples,
        bytes[] calldata proofs
    ) public virtual {
        return _mineWithFixedHash0(initHash0, shardId, miner, nonce, encodedSamples, proofs);
    }
}
