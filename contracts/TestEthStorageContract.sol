// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
        uint256 mask,
        bytes calldata inclusiveProof,
        bytes calldata decodeProof
    ) public view virtual override returns (bool) {
        PhyAddr memory kvInfo = kvMap[idxMap[kvIdx]];
        Proof memory proof = abi.decode(decodeProof, (Proof));

        // BLOB decoding check
        if (
            !decodeSample(proof, uint256(keccak256(abi.encode(kvInfo.hash, miner, kvIdx))), sampleIdxInKv, mask)
        ) {
            return false;
        }

        MerkleProof memory mProof = abi.decode(inclusiveProof, (MerkleProof));

        // Inclusive proof of decodedData = mask ^ encodedData
        if (!MerkleLib.verify(keccak256(abi.encode(mProof.data)), sampleIdxInKv, mProof.rootHash, mProof.proofs)) {
            return false;
        }
        uint256 expectedEncodedData = uint256(mProof.data) ^ mask;
        return bytes32(expectedEncodedData) == encodedData;
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
        uint256[] memory masks,
        bytes calldata randaoProof,
        bytes[] calldata inclusiveProofs,
        bytes[] calldata decodeProof
    ) internal {
        // Obtain the blockhash of the block number of recent blocks
        require(block.number - blockNumber <= 64, "block number too old");
        // To avoid stack too deep, we resue the hash0 instead of using randao
        bytes32 hash0 = RandaoLib.verifyHeaderAndGetRandao(block.number, randaoProof);
        // Estimate block timestamp
        uint256 mineTs = block.timestamp - (block.number - blockNumber) * 12;

        // Given a blockhash and a miner, we only allow sampling up to nonce limit times.
        require(nonce < nonceLimit, "nonce too big");

        // Check if the data matches the hash in metadata and obtain the solution hash.
        hash0 = keccak256(abi.encode(miner, hash0, nonce));
        hash0 = verifySamples(shardId, hash0, miner, encodedSamples, masks, inclusiveProofs, decodeProof);

        uint256 diff = _calculateDiffAndInitHashSingleShard(shardId, mineTs);

        _rewardMiner(shardId, miner, mineTs, diff);
    }

    function mine(
        uint256 blockNumber,
        uint256 shardId,
        address miner,
        uint256 nonce,
        bytes32[] memory encodedSamples,
        uint256[] memory masks,
        bytes calldata randaoProof,
        bytes[] calldata inclusiveProofs,
        bytes[] calldata decodeProof
    ) public virtual override {
        return _mineWithoutDiffCompare(blockNumber, shardId, miner, nonce, encodedSamples, masks, randaoProof, inclusiveProofs, decodeProof);
    }

    function _mineWithFixedHash0(
        bytes32 initHash0,
        uint256 shardId,
        address miner,
        uint256 nonce,
        bytes32[] memory encodedSamples,
        uint256[] memory masks,
        bytes[] calldata inclusiveProofs,
        bytes[] calldata decodeProof
    ) internal {
        // Obtain the blockhash of the block number of recent blocks
        uint256 mineTs = block.timestamp;

        // Given a blockhash and a miner, we only allow sampling up to nonce limit times.
        require(nonce < nonceLimit, "nonce too big");

        // Check if the data matches the hash in metadata and obtain the solution hash.
        bytes32 hash0 = verifySamples(shardId, initHash0, miner, encodedSamples, masks, inclusiveProofs, decodeProof);

        uint256 diff = _calculateDiffAndInitHashSingleShard(shardId, mineTs);

        _rewardMiner(shardId, miner, mineTs, diff);
    }

    function mineWithFixedHash0(
        bytes32 initHash0,
        uint256 shardId,
        address miner,
        uint256 nonce,
        bytes32[] memory encodedSamples,
        uint256[] memory masks,
        bytes[] calldata inclusiveProofs,
        bytes[] calldata decodeProof
    ) public virtual {
        return _mineWithFixedHash0(initHash0, shardId, miner, nonce, encodedSamples, masks, inclusiveProofs, decodeProof);
    }
}
