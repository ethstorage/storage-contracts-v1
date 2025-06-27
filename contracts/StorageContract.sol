// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./DecentralizedKV.sol";
import "./libraries/MiningLib.sol";
import "./libraries/RandaoLib.sol";

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

    /// @notice Role for whitelisted miners
    bytes32 public constant MINER_ROLE = keccak256("MINER_ROLE");

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

    /// @notice Prepaid timestamp of last mined
    uint256 public prepaidLastMineTime;

    /// @notice Fund tracker for prepaid
    uint256 public accPrepaidAmount;

    /// @notice a state variable to control the MINER_ROLE check
    bool public enforceMinerRole;

    /// @notice Reentrancy lock
    bool private transient locked;

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

    modifier nonReentrant() {
        require(!locked, "StorageContract: reentrancy attempt!");
        locked = true;
        _;
        // Unlocks the guard, making the pattern composable.
        // After the function exits, it can be called again, even in the same transaction.
        locked = false;
    }

    /// @notice Constructs the StorageContract contract. Initializes the storage config.
    constructor(Config memory _config, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor)
        DecentralizedKV(1 << _config.maxKvSizeBits, _startTime, _storageCost, _dcfFactor)
    {
        /* Assumptions */
        require(_config.shardSizeBits >= _config.maxKvSizeBits, "StorageContract: shardSize too small");
        require(_config.maxKvSizeBits >= SAMPLE_SIZE_BITS, "StorageContract: maxKvSize too small");
        require(_config.randomChecks > 0, "StorageContract: at least one checkpoint needed");

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
        enforceMinerRole = true;
    }

    /// @notice People can sent ETH to the contract.
    function sendValue() public payable {
        accPrepaidAmount += msg.value;
    }

    /// @notice Upfront payment for the next insertion
    function upfrontPayment() public view virtual override returns (uint256) {
        return _upfrontPaymentInBatch(kvEntryCount, 1);
    }

    /// @notice Upfront payment for a batch insertion
    /// @param _batchSize The blob count for a batch insertion.
    /// @return The total payment for a batch insertion.
    function upfrontPaymentInBatch(uint256 _batchSize) public view returns (uint256) {
        return _upfrontPaymentInBatch(kvEntryCount, _batchSize);
    }

    /// @notice Upfront payment for a batch insertion
    function _upfrontPaymentInBatch(uint256 _kvEntryCount, uint256 _batchSize) internal view returns (uint256) {
        uint256 shardId = _getShardId(_kvEntryCount);
        uint256 totalEntries = _kvEntryCount + _batchSize; // include the batch to be put
        uint256 totalPayment = 0;
        if (_getShardId(totalEntries) > shardId) {
            uint256 kvCountNew = totalEntries % (1 << SHARD_ENTRY_BITS);
            totalPayment += _upfrontPayment(_blockTs()) * kvCountNew;
            totalPayment += _upfrontPayment(infos[shardId].lastMineTime) * (_batchSize - kvCountNew);
        } else {
            totalPayment += _upfrontPayment(infos[shardId].lastMineTime) * _batchSize;
        }
        return totalPayment;
    }

    /// @inheritdoc DecentralizedKV
    function _checkAppend(uint256 _batchSize) internal virtual override {
        uint256 kvEntryCountPrev = kvEntryCount - _batchSize; // kvEntryCount already increased
        uint256 totalPayment = _upfrontPaymentInBatch(kvEntryCountPrev, _batchSize);
        require(msg.value >= totalPayment, "StorageContract: not enough batch payment");

        uint256 shardId = _getShardId(kvEntryCount); // shard id after the batch
        if (shardId > _getShardId(kvEntryCountPrev)) {
            // Open a new shard and mark the shard is ready to mine.
            // (TODO): Setup shard difficulty as current difficulty / factor?
            infos[shardId].lastMineTime = _blockTs();
        }
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
    function _calculateDiffAndInitHashSingleShard(uint256 _shardId, uint256 _minedTs)
        internal
        view
        returns (uint256 diff_)
    {
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
        (bool updatePrepaidTime, uint256 prepaidAmountSaved, uint256 treasuryReward, uint256 minerReward) =
            _miningReward(_shardId, _minedTs);
        if (updatePrepaidTime) {
            prepaidLastMineTime = _minedTs;
        }
        accPrepaidAmount += prepaidAmountSaved + treasuryReward;
        // Update mining info.
        MiningLib.update(infos[_shardId], _minedTs, _diff);

        require(minerReward <= address(this).balance, "StorageContract: not enough balance");
        // Actually `transfer` is limited by the amount of gas allocated, which is not sufficient to enable reentrancy attacks.
        // However, this behavior may restrict the extensibility of scenarios where the receiver is a contract that requires
        // additional gas for its fallback functions of proper operations.
        // Therefore, we still use a reentrancy guard (`nonReentrant`) in case `call` replaces `transfer` in the future.
        payable(_miner).transfer(minerReward);
        emit MinedBlock(_shardId, _diff, infos[_shardId].blockMined, _minedTs, _miner, minerReward);
    }

    /// @notice Calculate the mining reward
    /// @param _shardId  The shard id.
    /// @param _minedTs  The mined timestamp.
    /// @return updatePrepaidTime Whether to update the prepaid time.
    /// @return prepaidAmountSaved The capped part of prepaid amount.
    /// @return treasuryReward    The treasury reward.
    /// @return minerReward       The miner reward.
    function _miningReward(uint256 _shardId, uint256 _minedTs)
        internal
        view
        returns (bool, uint256, uint256, uint256)
    {
        MiningLib.MiningInfo storage info = infos[_shardId];
        uint256 lastShardIdx = _getShardId(kvEntryCount);
        bool updatePrepaidTime = false;
        uint256 prepaidAmountSaved = 0;
        uint256 reward = 0;
        if (_shardId < lastShardIdx) {
            reward = _paymentIn(STORAGE_COST << SHARD_ENTRY_BITS, info.lastMineTime, _minedTs);
        } else if (_shardId == lastShardIdx) {
            reward = _paymentIn(STORAGE_COST * (kvEntryCount % (1 << SHARD_ENTRY_BITS)), info.lastMineTime, _minedTs);
            // Additional prepaid for the last shard
            if (prepaidLastMineTime < _minedTs) {
                uint256 fullReward = _paymentIn(STORAGE_COST << SHARD_ENTRY_BITS, info.lastMineTime, _minedTs);
                uint256 prepaidAmountIn = _paymentIn(prepaidAmount, prepaidLastMineTime, _minedTs);
                uint256 rewardCap = fullReward - reward;
                if (prepaidAmountIn > rewardCap) {
                    prepaidAmountSaved = prepaidAmountIn - rewardCap;
                    prepaidAmountIn = rewardCap;
                }
                reward += prepaidAmountIn;
                updatePrepaidTime = true;
            }
        }

        uint256 treasuryReward = (reward * TREASURY_SHARE) / 10000;
        uint256 minerReward = reward - treasuryReward;
        return (updatePrepaidTime, prepaidAmountSaved, treasuryReward, minerReward);
    }

    /// @notice Get the mining reward.
    /// @param _shardId     The shard id.
    /// @param _blockNum The block number.
    /// @return The mining reward.
    function miningReward(uint256 _shardId, uint256 _blockNum) public view returns (uint256) {
        uint256 minedTs = _getMinedTs(_blockNum);
        (,,, uint256 minerReward) = _miningReward(_shardId, minedTs);
        return minerReward;
    }

    /// @notice Mine a block.
    /// @param _blockNum     The block number.
    /// @param _shardId         The shard id.
    /// @param _miner           The miner address.
    /// @param _nonce           The nonce.
    /// @param _encodedSamples  The encoded samples.
    /// @param _masks           The masks of the samples.
    /// @param _randaoProof     The randao proof.
    /// @param _inclusiveProofs The inclusive proofs.
    /// @param _decodeProof     The decode proof.
    function mine(
        uint256 _blockNum,
        uint256 _shardId,
        address _miner,
        uint256 _nonce,
        bytes32[] memory _encodedSamples,
        uint256[] memory _masks,
        bytes calldata _randaoProof,
        bytes[] calldata _inclusiveProofs,
        bytes[] calldata _decodeProof
    ) public virtual nonReentrant {
        if (enforceMinerRole) {
            require(hasRole(MINER_ROLE, _miner), "StorageContract: miner not whitelisted");
        }
        _mine(
            _blockNum, _shardId, _miner, _nonce, _encodedSamples, _masks, _randaoProof, _inclusiveProofs, _decodeProof
        );
    }

    /// @notice Set the nonce limit.
    function setNonceLimit(uint256 _nonceLimit) public onlyRole(DEFAULT_ADMIN_ROLE) {
        nonceLimit = _nonceLimit;
    }

    /// @notice Set the prepaid amount.
    function setPrepaidAmount(uint256 _prepaidAmount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        prepaidAmount = _prepaidAmount;
    }

    /// @notice Set the treasury address.
    function setMinimumDiff(uint256 _minimumDiff) public onlyRole(DEFAULT_ADMIN_ROLE) {
        minimumDiff = _minimumDiff;
    }

    /// @notice Enable or disable the MINER_ROLE check.
    /// @param _enforceMinerRole Boolean to enable or disable the check.
    function setEnforceMinerRole(bool _enforceMinerRole) public onlyRole(DEFAULT_ADMIN_ROLE) {
        enforceMinerRole = _enforceMinerRole;
    }

    /// @notice On-chain verification of storage proof of sufficient sampling.
    ///         On-chain verifier will go same routine as off-chain data host, will check the encoded samples by decoding
    ///         to decoded one. The decoded samples will be used to perform inclusive check with on-chain datahashes.
    ///         The encoded samples will be used to calculate the solution hash, and if the hash passes the difficulty check,
    ///         the miner, or say the storage provider, shall be rewarded by the token number from out economic models
    /// @param _blockNum     The block number.
    /// @param _shardId         The shard id.
    /// @param _miner           The miner address.
    /// @param _nonce           The nonce.
    /// @param _encodedSamples  The encoded samples.
    /// @param _masks           The masks of the samples.
    /// @param _randaoProof     The randao proof.
    /// @param _inclusiveProofs The inclusive proofs.
    /// @param _decodeProof     The decode proof.
    function _mine(
        uint256 _blockNum,
        uint256 _shardId,
        address _miner,
        uint256 _nonce,
        bytes32[] memory _encodedSamples,
        uint256[] memory _masks,
        bytes calldata _randaoProof,
        bytes[] calldata _inclusiveProofs,
        bytes[] calldata _decodeProof
    ) internal virtual {
        require(_blockNumber() - _blockNum <= MAX_L1_MINING_DRIFT, "StorageContract: block number too old");
        // To avoid stack too deep, we resue the hash0 instead of using randao
        bytes32 hash0 = _getRandao(_blockNum, _randaoProof);
        // Estimate block timestamp
        uint256 mineTs = _getMinedTs(_blockNum);

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

    /// @notice Withdraw treasury fund
    function withdraw(uint256 _amount) public {
        require(accPrepaidAmount >= prepaidAmount + _amount, "StorageContract: not enough prepaid amount");
        accPrepaidAmount -= _amount;
        require(address(this).balance >= _amount, "StorageContract: not enough balance");
        payable(treasury).transfer(_amount);
    }

    /// @notice Get the current block number
    function _blockNumber() internal view virtual returns (uint256) {
        return block.number;
    }

    /// @notice Get the current block timestamp
    function _blockTs() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /// @notice Get the randao value by block number.
    function _getRandao(uint256 _blockNum, bytes calldata _headerRlpBytes) internal view virtual returns (bytes32) {
        bytes32 bh = blockhash(_blockNum);
        require(bh != bytes32(0), "StorageContract: failed to obtain blockhash");
        return RandaoLib.verifyHeaderAndGetRandao(bh, _headerRlpBytes);
    }

    /// @notice Get the mined timestamp
    function _getMinedTs(uint256 _blockNum) internal view returns (uint256) {
        return _blockTs() - (_blockNumber() - _blockNum) * 12;
    }

    /// @notice Get the shard id by kv entry count.
    function _getShardId(uint256 _kvEntryCount) internal view returns (uint256) {
        return _kvEntryCount > 0 ? (_kvEntryCount - 1) >> SHARD_ENTRY_BITS : 0;
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

    /// @notice Grant the MINER_ROLE to a miner address.
    function grantMinerRole(address _miner) public {
        grantRole(MINER_ROLE, _miner);
    }

    /// @notice Revoke the MINER_ROLE from a miner address.
    function revokeMinerRole(address _miner) public {
        revokeRole(MINER_ROLE, _miner);
    }
    /// @notice Check if a miner address has the MINER_ROLE.
    function hasMinerRole(address _miner) public view returns (bool) {
        return hasRole(MINER_ROLE, _miner);
    }
}
