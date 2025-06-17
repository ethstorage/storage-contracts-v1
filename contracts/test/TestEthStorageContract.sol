// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../EthStorageContract1.sol";
import "../libraries/MerkleLib.sol";

contract TestEthStorageContract is EthStorageContract1 {
    uint256 public currentTimestamp;

    struct MerkleProof {
        bytes32 data;
        bytes32 rootHash;
        bytes32[] proofs;
    }

    constructor(Config memory _config, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor)
        EthStorageContract1(_config, _startTime, _storageCost, _dcfFactor)
    {}

    function setTimestamp(uint256 ts) public {
        require(ts > currentTimestamp, "ts");
        currentTimestamp = ts;
    }

    function put(bytes32 key, bytes memory data) public payable {
        bytes32 dataHash = MerkleLib.merkleRootWithMinTree(data, 32);

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = key;
        bytes32[] memory dataHashes = new bytes32[](1);
        dataHashes[0] = dataHash;
        uint256[] memory lengths = new uint256[](1);
        lengths[0] = data.length;

        // TODO: 64-bytes should be more efficient.
        _putBatchInternal(keys, dataHashes, lengths);
    }

    function putBlob(bytes32 _key, uint256, /* _blobIdx */ uint256 _length) public payable override {
        bytes32 dataHash = bytes32(uint256(1 << 8 * 8));
        require(dataHash != 0, "EthStorageContract: failed to get blob hash");

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = _key;
        bytes32[] memory dataHashes = new bytes32[](1);
        dataHashes[0] = dataHash;
        uint256[] memory lengths = new uint256[](1);
        lengths[0] = _length;

        uint256[] memory kvIndices = _putBatchInternal(keys, dataHashes, lengths);

        emit PutBlob(kvIndices[0], _length, dataHash);
    }

    function putBlobs(bytes32[] memory _keys, uint256[] memory _blobIdxs, uint256[] memory _lengths)
        public
        payable
        override
    {
        require(_keys.length == _blobIdxs.length, "EthStorageContract: key length mismatch");
        require(_keys.length == _lengths.length, "EthStorageContract: length length mismatch");

        bytes32[] memory dataHashes = new bytes32[](_blobIdxs.length);
        for (uint256 i = 0; i < _blobIdxs.length; i++) {
            dataHashes[i] = bytes32(i + 1 << 8 * 8); // dummy data hash
            require(dataHashes[i] != 0, "EthStorageContract: failed to get blob hash");
        }

        uint256[] memory kvIdxs = _putBatchInternal(_keys, dataHashes, _lengths);

        for (uint256 i = 0; i < _blobIdxs.length; i++) {
            emit PutBlob(kvIdxs[i], _lengths[i], dataHashes[i]);
        }
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
        if (!decodeSample(proof, uint256(keccak256(abi.encode(kvInfo.hash, miner, kvIdx))), sampleIdxInKv, mask)) {
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
        uint256 rows = 1 << (SHARD_ENTRY_BITS + SAMPLE_LEN_BITS); // kvNumbersPerShard * smapleNumersPerKV

        uint256 parent = uint256(hash0) % rows;
        uint256 sampleIdx = parent + (startShardId << (SHARD_ENTRY_BITS + SAMPLE_LEN_BITS));
        uint256 kvIdx = sampleIdx >> SAMPLE_LEN_BITS;
        uint256 sampleIdxInKv = sampleIdx % (1 << SAMPLE_LEN_BITS);

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

    function getInitHash0(bytes32 randao, address miner, uint256 nonce) public pure returns (bytes32) {
        bytes32 hash0 = keccak256(abi.encode(miner, randao, nonce));
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
        require(_blockNumber() - blockNumber <= MAX_L1_MINING_DRIFT, "block number too old");
        bytes32 hash0 = _getRandao(blockNumber, randaoProof);
        uint256 mineTs = _getMinedTs(blockNumber);

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
        return _mineWithoutDiffCompare(
            blockNumber, shardId, miner, nonce, encodedSamples, masks, randaoProof, inclusiveProofs, decodeProof
        );
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
        verifySamples(shardId, initHash0, miner, encodedSamples, masks, inclusiveProofs, decodeProof);

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
        return
            _mineWithFixedHash0(initHash0, shardId, miner, nonce, encodedSamples, masks, inclusiveProofs, decodeProof);
    }
}
