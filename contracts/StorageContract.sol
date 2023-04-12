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
        uint256 shardSizeBits;
        uint256 randomChecks;
        uint256 minimumDiff;
        uint256 targetIntervalSec;
        uint256 cutoff;
        uint256 diffAdjDivisor;
        uint256 treasuryShare; // 10000 = 1.0
    }

    uint256 public constant sampleSizeBits = 5; // 32 bytes per sample

    uint256 public immutable maxKvSizeBits;
    uint256 public immutable shardSizeBits;
    uint256 public immutable shardEntryBits;
    uint256 public immutable sampleLenBits;
    uint256 public immutable randomChecks;
    uint256 public immutable minimumDiff;
    uint256 public immutable targetIntervalSec;
    uint256 public immutable cutoff;
    uint256 public immutable diffAdjDivisor;
    uint256 public immutable treasuryShare; // 10000 = 1.0
    uint256 public immutable prepaidAmount;

    mapping(uint256 => MiningLib.MiningInfo) public infos;
    uint256 public nonceLimit; // maximum nonce per block
    address public treasury;
    uint256 public prepaidLastMineTime;

    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury,
        uint256 _prepaidAmount
    ) payable DecentralizedKV(1 << _config.maxKvSizeBits, _startTime, _storageCost, _dcfFactor) {
        /* Assumptions */
        require(_config.shardSizeBits >= _config.maxKvSizeBits, "shardSize too small");
        require(_config.maxKvSizeBits >= sampleSizeBits, "maxKvSize too small");
        require(_config.randomChecks > 0, "At least one checkpoint needed");

        shardSizeBits = _config.shardSizeBits;
        maxKvSizeBits = _config.maxKvSizeBits;
        shardEntryBits = _config.shardSizeBits - _config.maxKvSizeBits;
        sampleLenBits = _config.maxKvSizeBits - sampleSizeBits;
        randomChecks = _config.randomChecks;
        minimumDiff = _config.minimumDiff;
        targetIntervalSec = _config.targetIntervalSec;
        cutoff = _config.cutoff;
        diffAdjDivisor = _config.diffAdjDivisor;
        treasuryShare = _config.treasuryShare;
        nonceLimit = _nonceLimit;
        treasury = _treasury;
        prepaidAmount = _prepaidAmount;
        prepaidLastMineTime = _startTime;
    }

    function sendValue() public payable {}

    function _prepareAppendWithTimestamp(uint256 timestamp) internal {
        uint256 totalEntries = lastKvIdx + 1; // include the one to be put
        uint256 shardId = lastKvIdx >> shardEntryBits; // shard id of the new KV
        if ((totalEntries % (1 << shardEntryBits)) == 1) {
            // Open a new shard if the KV is the first one of the shard
            // and mark the shard is ready to mine.
            // (TODO): Setup shard difficulty as current difficulty / factor?
            infos[shardId].lastMineTime = timestamp;
        }

        require(msg.value >= _upfrontPayment(infos[shardId].lastMineTime), "not enough payment");
    }

    // Upfront payment for the next insertion
    function upfrontPayment() public view virtual override returns (uint256) {
        uint256 totalEntries = lastKvIdx + 1; // include the one to be put
        uint256 shardId = lastKvIdx >> shardEntryBits; // shard id of the new KV
        if ((totalEntries % (1 << shardEntryBits)) == 1) {
            // Open a new shard if the KV is the first one of the shard
            // and mark the shard is ready to mine.
            // (TODO): Setup shard difficulty as current difficulty / factor?
            return _upfrontPayment(block.timestamp);
        } else {
            return _upfrontPayment(infos[shardId].lastMineTime);
        }
    }

    function _prepareAppend() internal virtual override {
        return _prepareAppendWithTimestamp(block.timestamp);
    }

    /*
     * Decode the sample and check the decoded sample is included in the BLOB corresponding to on-chain datahashes.
     */
    function decodeAndCheckInclusive(
        uint256 sampleIdx,
        PhyAddr memory kvInfo,
        address miner,
        bytes32 encodedSamples,
        bytes calldata inclusiveProof
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
        bytes32[] memory encodedSamples,
        bytes[] calldata inclusiveProofs
    ) internal returns (bytes32) {
        require(encodedSamples.length == randomChecks, "data length mismatch");
        require(inclusiveProofs.length == randomChecks, "proof length mismatch");
        // calculate the number of samples range of the sample check
        uint256 rows = 1 << (shardEntryBits + shardLenBits + sampleLenBits);

        for (uint256 i = 0; i < randomChecks; i++) {
            uint256 parent = uint256(hash0) % rows;
            uint256 sampleIdx = parent + (startShardId << (shardEntryBits + sampleLenBits));
            uint256 kvIdx = sampleIdx >> sampleLenBits;
            uint256 sampleIdxInKv = sampleIdx % (1 << sampleLenBits);
            PhyAddr memory kvInfo = kvMap[idxMap[kvIdx]];

            require(
                decodeAndCheckInclusive(sampleIdxInKv, kvInfo, miner, encodedSamples[i], inclusiveProofs[i]),
                "invalid samples"
            );

            hash0 = keccak256(abi.encode(hash0, encodedSamples[i]));
        }
        return hash0;
    }

    // Obtain the difficulty of the shard
    function _calculateDiffAndInitHashSingleShard(
        uint256 shardId,
        uint256 minedTs
    ) internal view returns (uint256 diff) {
        MiningLib.MiningInfo storage info = infos[shardId];
        require(minedTs >= info.lastMineTime, "minedTs too small");
        diff = MiningLib.expectedDiff(info, minedTs, targetIntervalSec, cutoff, diffAdjDivisor, minimumDiff);
    }

    function _rewardMiner(uint256 shardId, address miner, uint256 minedTs, uint256 diff) internal {
        // Mining is successful.
        // Send reward to coinbase and miner.
        MiningLib.MiningInfo storage info = infos[shardId];
        uint256 lastShardIdx = (lastKvIdx - 1) >> shardEntryBits;
        uint256 reward = 0;
        if (shardId < lastShardIdx) {
            reward = _paymentIn(storageCost << shardEntryBits, info.lastMineTime, minedTs);
        } else if (shardId == lastShardIdx) {
            reward = _paymentIn(storageCost * (lastKvIdx % (1 << shardEntryBits)), info.lastMineTime, minedTs);
            // Additional prepaid for the last shard
            if (prepaidLastMineTime < minedTs) {
                reward += _paymentIn(prepaidAmount, prepaidLastMineTime, minedTs);
                prepaidLastMineTime = minedTs;
            }
        }

        // Update mining info.
        MiningLib.update(infos[shardId], minedTs, diff);

        uint256 treasuryReward = (reward * treasuryShare) / 10000;
        uint256 minerReward = reward - treasuryReward;
        // TODO: avoid reentrancy attack
        payable(treasury).transfer(treasuryReward);
        payable(miner).transfer(minerReward);
    }

    /*
     * On-chain verification of storage proof of sufficient sampling.
     * On-chain verifier will go same routine as off-chain data host, will check the encoded samples by decoding
     * to decoded one. The decoded samples will be used to perform inclusive check with on-chain datahashes.
     * The encoded samples will be used to calculate the solution hash, and if the hash passes the difficulty check,
     * the miner, or say the storage provider, shall be rewarded by the token number from out economic models
     */
    function _mine(
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
        hash0 = _verifySamples(shardId, 0, hash0, miner, encodedSamples, proofs);

        // Check difficulty
        uint256 diff = _calculateDiffAndInitHashSingleShard(shardId, mineTs);
        uint256 required = uint256(2 ** 256 - 1) / diff;
        require(uint256(hash0) <= required, "diff not match");

        // Reward the miner with the current timestamp. Note that, we use the fee in interval
        // [lastMiningTime, now) to reward the miner, which means the miner may collect more fee
        // by submitting the tx later at the risk of invaliding the tx if the blockhash expires.
        _rewardMiner(shardId, miner, mineTs, diff);
    }

    function mine(
        uint256 blockNumber,
        uint256 shardId,
        address miner,
        uint256 nonce,
        bytes32[] memory encodedSamples,
        bytes[] calldata proofs
    ) public virtual {
        return _mine(blockNumber, shardId, miner, nonce, encodedSamples, proofs);
    }
}
