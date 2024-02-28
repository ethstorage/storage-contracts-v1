// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DecentralizedKV.sol";
import "./MiningLib.sol";
import "./RandaoLib.sol";

/*
 * EthStorage L1 Contract with Decentralized KV Interface and Proof of Storage Verification.
 */
abstract contract StorageContract is DecentralizedKV {

    uint256 public constant sampleSizeBits = 5; // 32 bytes per sample

    // *********** immutable args ***************
    function maxKvSizeBits() public pure returns (uint256) {
        return _getArgUint256(4 * 32);
    }

    function shardSizeBits() public pure returns (uint256) {
        return _getArgUint256(5 * 32);
    }

    function shardEntryBits() public pure returns (uint256) {
        return _getArgUint256(6 * 32);
    }

    function sampleLenBits() public pure returns (uint256) {
        return _getArgUint256(7 * 32);
    }

    function randomChecks() public pure returns (uint256) {
        return _getArgUint256(8 * 32);
    }

    function cutoff() public pure returns (uint256) {
        return _getArgUint256(9 * 32);
    }

    function diffAdjDivisor() public pure returns (uint256) {
        return _getArgUint256(10 * 32);
    }

    function treasuryShare() public pure returns (uint256) {// 10000 = 1.0
        return _getArgUint256(11 * 32);
    }
    // *********** immutable args ***************

    mapping(uint256 => MiningLib.MiningInfo) public infos;
    uint256 public nonceLimit; // maximum nonce per block
    address public treasury;
    uint256 public prepaidLastMineTime;
    uint256 public minimumDiff;
    uint256 public prepaidAmount;

    function __init_storage(
        uint256 _minimumDiff,
        uint256 _startTime,
        uint256 _nonceLimit,
        uint256 _prepaidAmount,
        address _treasury,
        address _owner
    ) public onlyInitializing {
        /* Assumptions */
        __init_KV(_owner);

        minimumDiff = _minimumDiff;
        nonceLimit = _nonceLimit;
        prepaidAmount = _prepaidAmount;
        treasury = _treasury;
        prepaidLastMineTime = _startTime;
        // make sure shard0 is ready to mine and pay correctly
        infos[0].lastMineTime = _startTime;
    }

    event MinedBlock(
        uint256 indexed shardId,
        uint256 indexed difficulty,
        uint256 indexed blockMined,
        uint256 lastMineTime,
        address miner,
        uint256 minerReward
    );

    function sendValue() public payable {}

    function _prepareAppendWithTimestamp(uint256 timestamp) internal {
        uint256 totalEntries = lastKvIdx + 1; // include the one to be put
        uint256 shardId = lastKvIdx >> shardEntryBits (); // shard id of the new KV
        if ((totalEntries % (1 << shardEntryBits())) == 1) {
            // Open a new shard if the KV is the first one of the shard
            // and mark the shard is ready to mine.
            // (TODO): Setup shard difficulty as current difficulty / factor?
            if (shardId != 0) {
                // shard0 is already opened in constructor
                infos[shardId].lastMineTime = timestamp;
            }
        }

        require(msg.value >= _upfrontPayment(infos[shardId].lastMineTime), "not enough payment");
    }

    // Upfront payment for the next insertion
    function upfrontPayment() public view virtual override returns (uint256) {
        uint256 totalEntries = lastKvIdx + 1; // include the one to be put
        uint256 shardId = lastKvIdx >> shardEntryBits(); // shard id of the new KV
        // shard0 is already opened in constructor
        if ((totalEntries % (1 << shardEntryBits())) == 1 && shardId != 0) {
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
     * Verify the samples of the BLOBs by the miner (storage provider) including
     * - decode the samples
     * - check the inclusive of the samples
     * - calculate the final hash using
     */
    function verifySamples(
        uint256 startShardId,
        bytes32 hash0,
        address miner,
        bytes32[] memory encodedSamples,
        uint256[] memory masks,
        bytes[] calldata inclusiveProofs,
        bytes[] calldata decodeProof
    ) public view virtual returns (bytes32);

    // Obtain the difficulty of the shard
    function _calculateDiffAndInitHashSingleShard(
        uint256 shardId,
        uint256 minedTs
    ) internal view returns (uint256 diff) {
        MiningLib.MiningInfo storage info = infos[shardId];
        require(minedTs >= info.lastMineTime, "minedTs too small");
        diff = MiningLib.expectedDiff(info, minedTs, cutoff(), diffAdjDivisor(), minimumDiff);
    }

    function _rewardMiner(uint256 shardId, address miner, uint256 minedTs, uint256 diff) internal {
        // Mining is successful.
        // Send reward to coinbase and miner.
        (bool updatePrepaidTime, uint256 treasuryReward, uint256 minerReward) = _miningReward(shardId, minedTs);
        if (updatePrepaidTime) {
            prepaidLastMineTime = minedTs;
        }

        // Update mining info.
        MiningLib.update(infos[shardId], minedTs, diff);

        // TODO: avoid reentrancy attack
        payable(treasury).transfer(treasuryReward);
        payable(miner).transfer(minerReward);
        emit MinedBlock(shardId, diff, infos[shardId].blockMined, minedTs, miner, minerReward);
    }

    function _miningReward(uint256 shardId, uint256 minedTs) internal view returns (bool, uint256, uint256) {
        MiningLib.MiningInfo storage info = infos[shardId];
        uint256 lastShardIdx = lastKvIdx > 0 ? (lastKvIdx - 1) >> shardEntryBits() : 0;
        uint256 reward = 0;
        bool updatePrepaidTime = false;
        if (shardId < lastShardIdx) {
            reward = _paymentIn(storageCost() << shardEntryBits(), info.lastMineTime, minedTs);
        } else if (shardId == lastShardIdx) {
            reward = _paymentIn(storageCost() * (lastKvIdx % (1 << shardEntryBits())), info.lastMineTime, minedTs);
            // Additional prepaid for the last shard
            if (prepaidLastMineTime < minedTs) {
                reward += _paymentIn(prepaidAmount, prepaidLastMineTime, minedTs);
                updatePrepaidTime = true;
            }
        }

        uint256 treasuryReward = (reward * treasuryShare()) / 10000;
        uint256 minerReward = reward - treasuryReward;
        return (updatePrepaidTime, treasuryReward, minerReward);
    }

    function miningReward(uint256 shardId, uint256 blockNumber) public view returns (uint256) {
        uint256 minedTs = block.timestamp - (block.number - blockNumber) * 12;
        (,, uint256 minerReward) = _miningReward(shardId, minedTs);
        return minerReward;
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
        uint256[] memory masks,
        bytes calldata randaoProof,
        bytes[] calldata inclusiveProofs,
        bytes[] calldata decodeProof
    ) internal {
        // Obtain the blockhash of the block number of recent blocks
        require(block.number - blockNumber <= 64, "block number too old");
        // To avoid stack too deep, we resue the hash0 instead of using randao
        bytes32 hash0 = RandaoLib.verifyHistoricalRandao(blockNumber, randaoProof);
        // Estimate block timestamp
        uint256 mineTs = block.timestamp - (block.number - blockNumber) * 12;

        // Given a blockhash and a miner, we only allow sampling up to nonce limit times.
        require(nonce < nonceLimit, "nonce too big");

        // Check if the data matches the hash in metadata and obtain the solution hash.
        hash0 = keccak256(abi.encode(miner, hash0, nonce));
        hash0 = verifySamples(shardId, hash0, miner, encodedSamples, masks, inclusiveProofs, decodeProof);

        // Check difficulty
        uint256 diff = _calculateDiffAndInitHashSingleShard(shardId, mineTs);
        uint256 required = uint256(2 ** 256 - 1) / diff;
        require(uint256(hash0) <= required, "diff not match");

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
    ) public virtual {
        return _mine(blockNumber, shardId, miner, nonce, encodedSamples, masks, randaoProof, inclusiveProofs, decodeProof);
    }

    function setPrepaidAmount(uint256 _prepaidAmount) public onlyOwner {
        prepaidAmount = _prepaidAmount;
    }

    function setMinimumDiff(uint256 _minimumDiff) public onlyOwner {
        minimumDiff = _minimumDiff;
    }
}
