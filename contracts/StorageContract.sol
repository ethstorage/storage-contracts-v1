// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DecentralizedKV.sol";
import "./MiningLib.sol";

/*
 * EthStorage L1 Contract with Decentralized KV Interface and Proof of Storage Verification.
 */
abstract contract StorageContract is DecentralizedKV {
    struct Config {
        uint256 maxKvSizeBits;
        uint256 chunkSizeBits;
        uint256 shardSizeBits;
        uint256 randomChecks;
        uint256 minimumDiff;
        uint256 targetIntervalSec;
        uint256 cutoff;
        uint256 diffAdjDivisor;
        uint256 coinbaseShare; // 10000 = 1.0
        ISystemContractDaggerHashimoto systemContract;
    }

    uint256 public immutable maxKvSizeBits;
    uint256 public immutable shardSizeBits;
    uint256 public immutable shardEntryBits;
    uint256 public immutable chunkLenBits;
    uint256 public immutable randomChecks;
    uint256 public immutable minimumDiff;
    uint256 public immutable targetIntervalSec;
    uint256 public immutable cutoff;
    uint256 public immutable diffAdjDivisor;
    uint256 public immutable coinbaseShare; // 10000 = 1.0
    ISystemContractDaggerHashimoto public immutable systemContract;

    mapping(uint256 => MiningLib.MiningInfo) public infos;
    uint256 public nonceLimit;          // maximum nonce per block
    address public treasury;

    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury
    )
        payable
        DecentralizedKV(
            _config.systemContract,
            1 << _config.maxKvSizeBits,
            1 << _config.chunkSizeBits,
            _startTime,
            _storageCost,
            _dcfFactor
        )
    {
        /* Assumptions */
        require(_config.shardSizeBits >= _config.maxKvSizeBits, "shardSize too small");
        require(_config.maxKvSizeBits >= _config.chunkSizeBits, "maxKvSize too small");
        require(_config.randomChecks > 0, "At least one checkpoint needed");

        systemContract = _config.systemContract;
        shardSizeBits = _config.shardSizeBits;
        maxKvSizeBits = _config.maxKvSizeBits;
        shardEntryBits = _config.shardSizeBits - _config.maxKvSizeBits;
        chunkLenBits = _config.maxKvSizeBits - _config.chunkSizeBits;
        randomChecks = _config.randomChecks;
        minimumDiff = _config.minimumDiff;
        targetIntervalSec = _config.targetIntervalSec;
        cutoff = _config.cutoff;
        diffAdjDivisor = _config.diffAdjDivisor;
        coinbaseShare = _config.coinbaseShare;
        // Shard 0 and 1 is ready to mine.
        infos[0].lastMineTime = _startTime;
        infos[1].lastMineTime = _startTime;
        nonceLimit = _nonceLimit;
        treasury = _treasury;
    }

    function sendValue() public payable {}

    function _preparePutWithTimestamp(uint256 timestamp) internal {
        if (((lastKvIdx + 1) % (1 << shardEntryBits)) == 0) {
            // Open a new shard.
            // The current shard should be already mined.
            // The next shard is ready to mine (although it has no data).
            // (TODO): Setup shard difficulty as current difficulty / factor?
            // The previous put must cover payment from [lastMineTime, inf) >= that of [block.timestamp, inf)
            uint256 nextShardId = ((lastKvIdx + 1) >> shardEntryBits) + 1;
            infos[nextShardId].lastMineTime = timestamp;
        }
    }

    function _preparePut() internal virtual override {
        return _preparePutWithTimestamp(block.timestamp);
    }

    /*
     * Decode the sample and check the decoded sample is included in the BLOB corresponding to on-chain datahashes.
     */
    function decodeAndCheckInclusive(
        uint256 chunkIdx,
        PhyAddr memory kvInfo,
        address miner,
        bytes memory encodedData,
        bytes memory inclusiveProof
    ) public view virtual returns (bool);

    /*
     * Verify the samples of the BLOBs by the miner (storage provider) including
     * - decode the samples
     * - check the inclusive of the samples
     * - calculate the final hash using
     */
    function _verifySamples(
        uint256 startShardId,
        uint256 shardLenBits,
        bytes32 hash0,
        address miner,
        bytes[] memory inclusiveProof,
        bytes[] memory maskedData
    ) internal view returns (bytes32) {
        require(maskedData.length == randomChecks, "data length mismatch");
        require(inclusiveProof.length == randomChecks, "proof length mismatch");
        // calculate the number of chunks range of the sample check
        uint256 rows = 1 << (shardEntryBits + shardLenBits + chunkLenBits);

        for (uint256 i = 0; i < randomChecks; i++) {
            uint256 mChunkSize = chunkSize;
            require(maskedData[i].length == mChunkSize, "invalid sample size");
            uint256 parent = uint256(hash0) % rows;
            uint256 chunkIdx = parent + (startShardId << (shardEntryBits + chunkLenBits));
            uint256 kvIdx = chunkIdx >> chunkLenBits;
            PhyAddr memory kvInfo = kvMap[idxMap[kvIdx]];

            require(decodeAndCheckInclusive(chunkIdx, kvInfo, miner, maskedData[i], inclusiveProof[i]), "invalid samples");

            /* NOTICE: we should use the maskedChunkData merged with the `hash0` to calculate the new `hash0`
             *          because the miner executes this `hash0` calculation off-chain in this way. */
            bytes memory maskedChunkData = maskedData[i];
            assembly {
                mstore(maskedChunkData, hash0)
                hash0 := keccak256(maskedChunkData, add(mChunkSize, 0x20))
                mstore(maskedChunkData, mChunkSize)
            }
        }
        return hash0;
    }

    // obtain the difficulty of the shard
    function _calculateDiffAndInitHashSingleShard(
        uint256 shardId,
        uint256 minedTs
    )
        internal
        view
        returns (
            uint256 diff
        )
    {
        MiningLib.MiningInfo storage info = infos[shardId];
        require(minedTs >= info.lastMineTime, "minedTs too small");
        diff = MiningLib.expectedDiff(info, minedTs, targetIntervalSec, cutoff, diffAdjDivisor, minimumDiff);
    }

    function lastMinableShardIdx() public view returns (uint256) {
        return (lastKvIdx >> shardEntryBits) + 1;
    }

    function _rewardMiner(
        uint256 shardId,
        address miner,
        uint256 minedTs,
        uint256 diff
    ) internal {
        // Mining is successful.
        // Send reward to coinbase and miner.
        uint256 totalReward = 0;
        uint256 lastPayableShardIdx = lastMinableShardIdx();

        if (shardId <= lastPayableShardIdx) {
            // Make a full shard payment.
            MiningLib.MiningInfo storage info = infos[shardId];
            totalReward += _paymentIn(storageCost << shardEntryBits, info.lastMineTime, minedTs);

            // Update mining info.
            MiningLib.update(infos[shardId], minedTs, diff);
        }
        uint256 treasuryReward = (totalReward * coinbaseShare) / 10000;
        uint256 minerReward = totalReward - treasuryReward;
        // TODO: avoid reentrancy attack
        payable(treasury).transfer(treasuryReward);
        payable(miner).transfer(minerReward);
    }

    /* In fact, this is on-chain function used for verifying whether what a miner claims,
       is satisfying the truth, or not.
       Nonce, along with maskedData, associated with mineTs and idx, are proof.
       On-chain verifier will go same routine as off-chain data host, will check the soundness of data,
       by running hashimoto algorithm, to get hash H. Then if it passes the difficulty check,
       the miner, or say the proof provider, shall be rewarded by the token number from out economic models */
    function _mine(
        uint256 blockNumber,
        uint256 startShardId,
        uint256 shardLenBits,
        address miner,
        uint256 minedTs,
        uint256 nonce,
        bytes[] memory proof,
        bytes[] memory maskedData
    ) internal {
        // obtain the blockhash of the block number
        bytes32 bh = blockhash(blockNumber);
        require(bh != bytes32(0), "failed to obtain blockhash");
        // given a blockhash and a miner, we only allow sampling up to nonce times.
        require(nonce < nonceLimit, "nonce too big");
        // obtain estimate mined time (TODO: prove timestamp of the header)
        // TODO: old timestamp may be incorrect for fee
        minedTs = block.timestamp - (block.number - blockNumber) * 12;
        uint256 shardLen = 1 << shardLenBits;
        // only allow storage proof on a single shard
        require(shardLen == 1, "shardLenBits must be 0");
        uint256 diff = _calculateDiffAndInitHashSingleShard(startShardId, minedTs);

        bytes32 hash0 = keccak256(abi.encode(miner, bh, nonce));
        hash0 = _verifySamples(startShardId, shardLenBits, hash0, miner, proof, maskedData);

        // Check if the data matches the hash in metadata.
        {
            uint256 required = uint256(2**256 - 1) / diff;
            require(uint256(hash0) <= required, "diff not match");
        }

        _rewardMiner(startShardId, miner, minedTs, diff);
    }

    // We allow cross mine multiple shards by aggregating their difficulties.
    // For some reasons, we never use checkIdList but if we remove it, we will get
    // a `Stack too deap error`
    function mine(
        uint256 blockNumber,
        uint256 startShardId,
        uint256 shardLenBits,
        address miner,
        uint256 minedTs,
        uint256 nonce,
        bytes[] memory proof,
        bytes[] memory maskedData
    ) public virtual {
        return _mine(blockNumber, startShardId, shardLenBits, miner, minedTs, nonce, proof, maskedData);
    }
}
