// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DecentralizedKV.sol";
import "./MiningLib.sol";
import "./RandaoLib.sol";

/// @custom:upgradeable
/// @title StorageContract
/// @notice EthStorage L1 Contract with Decentralized KV Interface and Proof of Storage Verification
abstract contract StorageContract is DecentralizedKV {
    /// @notice Represents the configuration of the storage contract.
    /// @custom:field maxKvSizeBits  Maximum size of a single key-value pair.
    /// @custom:field shardSizeBits  Storage shard size.
    /// @custom:field randomChecks   Number of random checks when mining
    /// @custom:field cutoff         Cutoff time for difficulty adjustment.
    /// @custom:field diffAdjDivisor Difficulty adjustment divisor.
    /// @custom:field treasuryShare  Treasury share in basis points. 10000 = 1.0
    struct Config {
        uint256 maxKvSizeBits;
        uint256 shardSizeBits;
        uint256 randomChecks;
        uint256 cutoff;
        uint256 diffAdjDivisor;
        uint256 treasuryShare;
    }

    /// @notice 32 bytes per sample
    uint256 internal constant SAMPLE_SIZE_BITS = 5;

    /// @notice 64 blocks
    uint8 internal constant MAX_L1_MINING_DRIFT = 64;

    /// @notice Maximum size of a single key-value pair
    uint256 internal immutable MAX_KV_SIZE_BITS;

    /// @notice Storage shard size
    uint256 internal immutable SHARD_SIZE_BITS;

    /// @notice Key-value count per shard
    uint256 internal immutable SHARD_ENTRY_BITS;

    /// @notice Sample count per key-value pair
    uint256 internal immutable SAMPLE_LEN_BITS;

    /// @notice Number of random checks when mining
    uint256 internal immutable RANDOM_CHECKS;

    /// @notice Cutoff time for difficulty adjustment
    uint256 internal immutable CUTOFF;

    /// @notice Difficulty adjustment divisor
    uint256 internal immutable DIFF_ADJ_DIVISOR;

    /// @notice Treasury share in basis points.
    uint256 internal immutable TREASURY_SHARE;

    /// @custom:spacer maxKvSizeBits, shardSizeBits, shardEntryBits, sampleLenBits, randomChecks
    /// @notice Spacer for backwards compatibility.
    uint256[5] private storSpacers1;

    /// @notice Minimum difficulty
    uint256 public minimumDiff;

    /// @custom:spacer cutoff, diffAdjDivisor, treasuryShare
    /// @notice Spacer for backwards compatibility.
    uint256[3] private storSpacers2;

    /// @notice Prepaid amount for the last shard
    uint256 public prepaidAmount;

    /// @notice Mining infomation for each shard
    mapping(uint256 => MiningLib.MiningInfo) public infos;

    /// @notice Maximum nonce per block
    uint256 public nonceLimit;

    /// @notice Treasury address
    address public treasury;

    /// @notice
    uint256 public prepaidLastMineTime;

    // TODO: Reserve extra slots (to a total of 50?) in the storage layout for future upgrades

    /// @notice Emitted when a block is mined.
    /// @param shardId      The shard id of the mined block.
    /// @param difficulty   The difficulty of the mined block.
    /// @param blockMined   The block number of the mined block.
    /// @param lastMineTime The last mine time of the shard.
    /// @param miner        The miner of the block.
    /// @param minerReward  The reward of the miner.
    event MinedBlock(
        uint256 indexed shardId,
        uint256 indexed difficulty,
        uint256 indexed blockMined,
        uint256 lastMineTime,
        address miner,
        uint256 minerReward
    );

    /// @notice Constructs the StorageContract contract. Initializes the storage config.
    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor
    ) DecentralizedKV(1 << _config.maxKvSizeBits, _startTime, _storageCost, _dcfFactor) {
        /* Assumptions */
        require(_config.shardSizeBits >= _config.maxKvSizeBits, "StorageContract: shardSize too small");
        require(_config.maxKvSizeBits >= SAMPLE_SIZE_BITS, "StorageContract: maxKvSize too small");
        require(_config.randomChecks > 0, "StorageContract: At least one checkpoint needed");

        MAX_KV_SIZE_BITS = _config.maxKvSizeBits;
        SHARD_SIZE_BITS = _config.shardSizeBits;
        SHARD_ENTRY_BITS = _config.shardSizeBits - _config.maxKvSizeBits;
        SAMPLE_LEN_BITS = _config.maxKvSizeBits - SAMPLE_SIZE_BITS;
        RANDOM_CHECKS = _config.randomChecks;
        CUTOFF = _config.cutoff;
        DIFF_ADJ_DIVISOR = _config.diffAdjDivisor;
        TREASURY_SHARE = _config.treasuryShare;
    }

    /// @notice Initializer.
    /// @param _minimumDiff   The minimum difficulty.
    /// @param _prepaidAmount The prepaid amount for the last shard.
    /// @param _nonceLimit    The maximum nonce per block.
    /// @param _treasury      The treasury address.
    /// @param _owner         The contract owner.
    function __init_storage(
        uint256 _minimumDiff,
        uint256 _prepaidAmount,
        uint256 _nonceLimit,
        address _treasury,
        address _owner
    ) public onlyInitializing {
        __init_KV(_owner);

        minimumDiff = _minimumDiff;
        prepaidAmount = _prepaidAmount;
        nonceLimit = _nonceLimit;
        treasury = _treasury;
        prepaidLastMineTime = START_TIME;
        // make sure shard0 is ready to mine and pay correctly
        infos[0].lastMineTime = START_TIME;
    }

    /// @notice People can sent ETH to the contract.
    function sendValue() public payable {}

    /// @notice Checks the payment using the last mine time.
    function _prepareAppendWithTimestamp(uint256 _timestamp) internal {
        uint256 totalEntries = kvEntryCount + 1; // include the one to be put
        uint256 shardId = kvEntryCount >> SHARD_ENTRY_BITS; // shard id of the new KV
        if ((totalEntries % (1 << SHARD_ENTRY_BITS)) == 1) {
            // Open a new shard if the KV is the first one of the shard
            // and mark the shard is ready to mine.
            // (TODO): Setup shard difficulty as current difficulty / factor?
            if (shardId != 0) {
                // shard0 is already opened in constructor
                infos[shardId].lastMineTime = _timestamp;
            }
        }

        require(msg.value >= _upfrontPayment(infos[shardId].lastMineTime), "StorageContract: not enough payment");
    }

    /// @notice Upfront payment for the next insertion
    function upfrontPayment() public view virtual override returns (uint256) {
        uint256 totalEntries = kvEntryCount + 1; // include the one to be put
        uint256 shardId = kvEntryCount >> SHARD_ENTRY_BITS; // shard id of the new KV
        // shard0 is already opened in constructor
        if ((totalEntries % (1 << SHARD_ENTRY_BITS)) == 1 && shardId != 0) {
            // Open a new shard if the KV is the first one of the shard
            // and mark the shard is ready to mine.
            // (TODO): Setup shard difficulty as current difficulty / factor?
            return _upfrontPayment(block.timestamp);
        } else {
            return _upfrontPayment(infos[shardId].lastMineTime);
        }
    }

    /// @inheritdoc DecentralizedKV
    function _prepareAppend() internal virtual override {
        return _prepareAppendWithTimestamp(block.timestamp);
    }

    /// @notice Verify the samples of the BLOBs by the miner (storage provider) including
    ///         - decode the samples
    ///         - check the inclusive of the samples
    ///         - calculate the final hash using
    /// @param _startShardId    The shard id of the start shard.
    /// @param _hash0           The hash0 of the mining block.
    /// @param _miner           The miner address.
    /// @param _encodedSamples  The encoded samples.
    /// @param _masks           The masks of the samples.
    /// @param _inclusiveProofs The inclusive proofs of the samples.
    /// @param _decodeProof     The decode proof of the samples.
    /// @return The mining result.
    function verifySamples(
        uint256 _startShardId,
        bytes32 _hash0,
        address _miner,
        bytes32[] memory _encodedSamples,
        uint256[] memory _masks,
        bytes[] calldata _inclusiveProofs,
        bytes[] calldata _decodeProof
    ) public view virtual returns (bytes32);

    /// @notice Obtain the difficulty of the shard
    /// @param _shardId  The shard id.
    /// @param _minedTs  The mined timestamp.
    /// @return diff_ The difficulty of the shard.
    function _calculateDiffAndInitHashSingleShard(
        uint256 _shardId,
        uint256 _minedTs
    ) internal view returns (uint256 diff_) {
        MiningLib.MiningInfo storage info = infos[_shardId];
        require(_minedTs >= info.lastMineTime, "StorageContract: minedTs too small");
        diff_ = MiningLib.expectedDiff(info, _minedTs, CUTOFF, DIFF_ADJ_DIVISOR, minimumDiff);
    }

    /// @notice Reward the miner
    /// @param _shardId  The shard id.
    /// @param _miner    The miner address.
    /// @param _minedTs  The mined timestamp.
    /// @param _diff     The difficulty of the shard.
    function _rewardMiner(uint256 _shardId, address _miner, uint256 _minedTs, uint256 _diff) internal {
        // Mining is successful.
        // Send reward to coinbase and miner.
        (bool updatePrepaidTime, uint256 treasuryReward, uint256 minerReward) = _miningReward(_shardId, _minedTs);
        if (updatePrepaidTime) {
            prepaidLastMineTime = _minedTs;
        }

        // Update mining info.
        MiningLib.update(infos[_shardId], _minedTs, _diff);

        require(treasuryReward + minerReward <= address(this).balance, "StorageContract: not enough balance");
        // TODO: avoid reentrancy attack
        payable(treasury).transfer(treasuryReward);
        payable(_miner).transfer(minerReward);
        emit MinedBlock(_shardId, _diff, infos[_shardId].blockMined, _minedTs, _miner, minerReward);
    }

    /// @notice Calculate the mining reward
    /// @param _shardId  The shard id.
    /// @param _minedTs  The mined timestamp.
    /// @return updatePrepaidTime Whether to update the prepaid time.
    /// @return treasuryReward    The treasury reward.
    /// @return minerReward       The miner reward.
    function _miningReward(uint256 _shardId, uint256 _minedTs) internal view returns (bool, uint256, uint256) {
        MiningLib.MiningInfo storage info = infos[_shardId];
        uint256 lastShardIdx = kvEntryCount > 0 ? (kvEntryCount - 1) >> SHARD_ENTRY_BITS : 0;
        uint256 reward = 0;
        bool updatePrepaidTime = false;
        if (_shardId < lastShardIdx) {
            reward = _paymentIn(STORAGE_COST << SHARD_ENTRY_BITS, info.lastMineTime, _minedTs);
        } else if (_shardId == lastShardIdx) {
            reward = _paymentIn(STORAGE_COST * (kvEntryCount % (1 << SHARD_ENTRY_BITS)), info.lastMineTime, _minedTs);
            // Additional prepaid for the last shard
            if (prepaidLastMineTime < _minedTs) {
                reward += _paymentIn(prepaidAmount, prepaidLastMineTime, _minedTs);
                updatePrepaidTime = true;
            }
        }

        uint256 treasuryReward = (reward * TREASURY_SHARE) / 10000;
        uint256 minerReward = reward - treasuryReward;
        return (updatePrepaidTime, treasuryReward, minerReward);
    }

    /// @notice Get the mining reward.
    /// @param _shardId     The shard id.
    /// @param _blockNumber The block number.
    /// @return The mining reward.
    function miningReward(uint256 _shardId, uint256 _blockNumber) public view returns (uint256) {
        uint256 minedTs = block.timestamp - (block.number - _blockNumber) * 12;
        (, , uint256 minerReward) = _miningReward(_shardId, minedTs);
        return minerReward;
    }

    /// @notice Mine a block.
    /// @param _blockNumber     The block number.
    /// @param _shardId         The shard id.
    /// @param _miner           The miner address.
    /// @param _nonce           The nonce.
    /// @param _encodedSamples  The encoded samples.
    /// @param _masks           The masks of the samples.
    /// @param _randaoProof     The randao proof.
    /// @param _inclusiveProofs The inclusive proofs.
    /// @param _decodeProof     The decode proof.
    function mine(
        uint256 _blockNumber,
        uint256 _shardId,
        address _miner,
        uint256 _nonce,
        bytes32[] memory _encodedSamples,
        uint256[] memory _masks,
        bytes calldata _randaoProof,
        bytes[] calldata _inclusiveProofs,
        bytes[] calldata _decodeProof
    ) public virtual {
        _mine(
            _blockNumber,
            _shardId,
            _miner,
            _nonce,
            _encodedSamples,
            _masks,
            _randaoProof,
            _inclusiveProofs,
            _decodeProof
        );
    }

    /// @notice Set the nonce limit.
    function setNonceLimit(uint256 _nonceLimit) public onlyOwner {
        nonceLimit = _nonceLimit;
    }

    /// @notice Set the prepaid amount.
    function setPrepaidAmount(uint256 _prepaidAmount) public onlyOwner {
        prepaidAmount = _prepaidAmount;
    }

    /// @notice Set the treasury address.
    function setMinimumDiff(uint256 _minimumDiff) public onlyOwner {
        minimumDiff = _minimumDiff;
    }

    /// @notice On-chain verification of storage proof of sufficient sampling.
    ///         On-chain verifier will go same routine as off-chain data host, will check the encoded samples by decoding
    ///         to decoded one. The decoded samples will be used to perform inclusive check with on-chain datahashes.
    ///         The encoded samples will be used to calculate the solution hash, and if the hash passes the difficulty check,
    ///         the miner, or say the storage provider, shall be rewarded by the token number from out economic models
    /// @param _blockNumber     The block number.
    /// @param _shardId         The shard id.
    /// @param _miner           The miner address.
    /// @param _nonce           The nonce.
    /// @param _encodedSamples  The encoded samples.
    /// @param _masks           The masks of the samples.
    /// @param _randaoProof     The randao proof.
    /// @param _inclusiveProofs The inclusive proofs.
    /// @param _decodeProof     The decode proof.
    function _mine(
        uint256 _blockNumber,
        uint256 _shardId,
        address _miner,
        uint256 _nonce,
        bytes32[] memory _encodedSamples,
        uint256[] memory _masks,
        bytes calldata _randaoProof,
        bytes[] calldata _inclusiveProofs,
        bytes[] calldata _decodeProof
    ) internal virtual {
        // Obtain the blockhash of the block number of recent blocks
        require(block.number - _blockNumber <= MAX_L1_MINING_DRIFT, "StorageContract: block number too old");
        // To avoid stack too deep, we resue the hash0 instead of using randao
        bytes32 hash0 = RandaoLib.verifyHistoricalRandao(_blockNumber, _randaoProof);
        // Estimate block timestamp
        uint256 mineTs = block.timestamp - (block.number - _blockNumber) * 12;

        // Given a blockhash and a miner, we only allow sampling up to nonce limit times.
        require(_nonce < nonceLimit, "StorageContract: nonce too big");

        // Check if the data matches the hash in metadata and obtain the solution hash.
        hash0 = keccak256(abi.encode(_miner, hash0, _nonce));
        hash0 = verifySamples(_shardId, hash0, _miner, _encodedSamples, _masks, _inclusiveProofs, _decodeProof);

        // Check difficulty
        uint256 diff = _calculateDiffAndInitHashSingleShard(_shardId, mineTs);
        uint256 required = uint256(2 ** 256 - 1) / diff;
        require(uint256(hash0) <= required, "StorageContract: diff not match");

        _rewardMiner(_shardId, _miner, mineTs, diff);
    }

    /// @notice Return the sample size bits.
    function sampleSizeBits() public pure returns (uint256) {
        return SAMPLE_SIZE_BITS;
    }

    /// @notice Return the max L1 mining drift.
    function maxL1MiningDrift() public pure returns (uint8) {
        return MAX_L1_MINING_DRIFT;
    }

    /// @notice Return the max kv size bits.
    function maxKvSizeBits() public view returns (uint256) {
        return MAX_KV_SIZE_BITS;
    }

    /// @notice Return the shard size bits.
    function shardSizeBits() public view returns (uint256) {
        return SHARD_SIZE_BITS;
    }

    /// @notice Return the shard entry bits.
    function shardEntryBits() public view returns (uint256) {
        return SHARD_ENTRY_BITS;
    }

    /// @notice Return the sample len bits.
    function sampleLenBits() public view returns (uint256) {
        return SAMPLE_LEN_BITS;
    }

    /// @notice Return the random checks.
    function randomChecks() public view returns (uint256) {
        return RANDOM_CHECKS;
    }

    /// @notice Return the cutoff.
    function cutoff() public view returns (uint256) {
        return CUTOFF;
    }

    /// @notice Return the diff adj divisor.
    function diffAdjDivisor() public view returns (uint256) {
        return DIFF_ADJ_DIVISOR;
    }

    /// @notice Return the treasury share.
    function treasuryShare() public view returns (uint256) {
        return TREASURY_SHARE;
    }
}
