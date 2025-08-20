// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "./DecentralizedKV.sol";
import "./libraries/MiningLib.sol";
import "./libraries/RandaoLib.sol";

/// @custom:upgradeable
/// @title StorageContract
/// @notice EthStorage L1 Contract with Decentralized KV Interface and Proof of Storage Verification
abstract contract StorageContract is DecentralizedKV, AccessControlUpgradeable {
    /// @notice Thrown when a reentrancy attempt is detected.
    error StorageContract_ReentrancyAttempt();

    /// @notice Thrown when the shard size is too small.
    error StorageContract_ShardSizeTooSmall();

    /// @notice Thrown when the max key-value size is too small.
    error StorageContract_MaxKvSizeTooSmall();

    /// @notice Thrown when at least one checkpoint is needed.
    error StorageContract_AtLeastOneCheckpointNeeded();

    /// @notice Thrown when the batch payment is not enough.
    error StorageContract_NotEnoughBatchPayment();

    /// @notice Thrown when the mined timestamp is too small.
    error StorageContract_MinedTsTooSmall();

    /// @notice Thrown when the miner reward is not enough.
    error StorageContract_NotEnoughMinerReward();

    /// @notice Thrown when the miner is not whitelisted.
    error StorageContract_MinerNotWhitelisted();

    /// @notice Thrown when the block number is too old.
    error StorageContract_BlockNumberTooOld();

    /// @notice Thrown when the nonce is too big.
    error StorageContract_NonceTooBig();

    /// @notice Thrown when the difficulty is not met.
    error StorageContract_DifficultyNotMet();

    /// @notice Thrown when the balance is not enough.
    error StorageContract_NotEnoughBalance();

    /// @notice Thrown when the blockhash is not obtained.
    error StorageContract_FailedToObtainBlockhash();

    /// @notice Thrown when the prepaid amount is not enough.
    error StorageContract_NotEnoughPrepaidAmount();

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

    /// @custom:storage-location erc7201:openzeppelin.storage.StorageContract
    struct StorageContractStorage {
        /// @notice Minimum difficulty
        uint256 _minimumDiff;
        /// @notice Prepaid amount for the last shard
        uint256 _prepaidAmount;
        /// @notice Mining infomation for each shard
        mapping(uint256 => MiningLib.MiningInfo) _infos;
        /// @notice Maximum nonce per block
        uint256 _nonceLimit;
        /// @notice Treasury address
        address _treasury;
        /// @notice Prepaid timestamp of last mined
        uint256 _prepaidLastMineTime;
        /// @notice Fund tracker for prepaid
        uint256 _accPrepaidAmount;
        /// @notice a state variable to control the MINER_ROLE check
        bool _enforceMinerRole;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.StorageContract")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant StorageContractStorageLocation =
        0x2e87afa02c4126794624df6162c63cb642521b7bea4fc2331190b8ab7e6a0f00;

    function _getStorageContractStorage() private pure returns (StorageContractStorage storage $) {
        assembly {
            $.slot := StorageContractStorageLocation
        }
    }

    /// @notice Reentrancy lock
    bool private transient locked;

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
        if (locked) {
            revert StorageContract_ReentrancyAttempt();
        }
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
        if (_config.shardSizeBits < _config.maxKvSizeBits) {
            revert StorageContract_ShardSizeTooSmall();
        }
        if (_config.maxKvSizeBits < SAMPLE_SIZE_BITS) {
            revert StorageContract_MaxKvSizeTooSmall();
        }
        if (_config.randomChecks == 0) {
            revert StorageContract_AtLeastOneCheckpointNeeded();
        }

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
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);

        __init_KV();

        StorageContractStorage storage $ = _getStorageContractStorage();
        $._minimumDiff = _minimumDiff;
        $._prepaidAmount = _prepaidAmount;
        $._nonceLimit = _nonceLimit;
        $._treasury = _treasury;
        $._prepaidLastMineTime = START_TIME;
        // make sure shard0 is ready to mine and pay correctly
        $._infos[0].lastMineTime = START_TIME;
        $._enforceMinerRole = true;
    }

    /// @notice People can sent ETH to the contract.
    function sendValue() public payable {
        StorageContractStorage storage $ = _getStorageContractStorage();
        $._accPrepaidAmount += msg.value;
    }

    /// @notice Upfront payment for the next insertion
    function upfrontPayment() public view virtual override returns (uint256) {
        return _upfrontPaymentInBatch(kvEntryCount(), 1);
    }

    /// @notice Upfront payment for a batch insertion
    /// @param _batchSize The blob count for a batch insertion.
    /// @return The total payment for a batch insertion.
    function upfrontPaymentInBatch(uint256 _batchSize) public view returns (uint256) {
        return _upfrontPaymentInBatch(kvEntryCount(), _batchSize);
    }

    /// @notice Upfront payment for a batch insertion
    function _upfrontPaymentInBatch(uint256 _kvEntryCount, uint256 _batchSize) internal view returns (uint256) {
        uint256 shardId = _getShardId(_kvEntryCount);
        uint256 totalEntries = _kvEntryCount + _batchSize; // include the batch to be put
        uint256 totalPayment = 0;

        StorageContractStorage storage $ = _getStorageContractStorage();
        if (_getShardId(totalEntries) > shardId) {
            uint256 kvCountNew = totalEntries % (1 << SHARD_ENTRY_BITS);
            totalPayment += _upfrontPayment(_blockTs()) * kvCountNew;
            totalPayment += _upfrontPayment($._infos[shardId].lastMineTime) * (_batchSize - kvCountNew);
        } else {
            totalPayment += _upfrontPayment($._infos[shardId].lastMineTime) * _batchSize;
        }
        return totalPayment;
    }

    /// @inheritdoc DecentralizedKV
    function _checkAppend(uint256 _batchSize) internal virtual override {
        uint256 kvEntryCountPrev = kvEntryCount() - _batchSize; // kvEntryCount already increased
        uint256 totalPayment = _upfrontPaymentInBatch(kvEntryCountPrev, _batchSize);

        if (msg.value < totalPayment) {
            revert StorageContract_NotEnoughBatchPayment();
        }

        uint256 shardId = _getShardId(kvEntryCount()); // shard id after the batch
        StorageContractStorage storage $ = _getStorageContractStorage();
        if (shardId > _getShardId(kvEntryCountPrev)) {
            // Open a new shard and mark the shard is ready to mine.
            // (TODO): Setup shard difficulty as current difficulty / factor?
            $._infos[shardId].lastMineTime = _blockTs();
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
        StorageContractStorage storage $ = _getStorageContractStorage();
        MiningLib.MiningInfo storage info = $._infos[_shardId];

        if (_minedTs < info.lastMineTime) {
            revert StorageContract_MinedTsTooSmall();
        }

        diff_ = MiningLib.expectedDiff(info, _minedTs, CUTOFF, DIFF_ADJ_DIVISOR, $._minimumDiff);
    }

    /// @notice Reward the miner
    /// @param _shardId  The shard id.
    /// @param _miner    The miner address.
    /// @param _minedTs  The mined timestamp.
    /// @param _diff     The difficulty of the shard.
    function _rewardMiner(uint256 _shardId, address _miner, uint256 _minedTs, uint256 _diff) internal {
        StorageContractStorage storage $ = _getStorageContractStorage();
        // Mining is successful.
        // Send reward to coinbase and miner.
        (bool updatePrepaidTime, uint256 prepaidAmountSaved, uint256 treasuryReward, uint256 minerReward) =
            _miningReward(_shardId, _minedTs);
        if (updatePrepaidTime) {
            $._prepaidLastMineTime = _minedTs;
        }
        $._accPrepaidAmount += prepaidAmountSaved + treasuryReward;
        // Update mining info.
        MiningLib.update($._infos[_shardId], _minedTs, _diff);

        if (minerReward > address(this).balance) {
            revert StorageContract_NotEnoughMinerReward();
        }
        // Actually `transfer` is limited by the amount of gas allocated, which is not sufficient to enable reentrancy attacks.
        // However, this behavior may restrict the extensibility of scenarios where the receiver is a contract that requires
        // additional gas for its fallback functions of proper operations.
        // Therefore, we still use a reentrancy guard (`nonReentrant`) in case `call` replaces `transfer` in the future.
        payable(_miner).transfer(minerReward);
        emit MinedBlock(_shardId, _diff, $._infos[_shardId].blockMined, _minedTs, _miner, minerReward);
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
        StorageContractStorage storage $ = _getStorageContractStorage();
        MiningLib.MiningInfo storage info = $._infos[_shardId];
        uint256 lastShardIdx = _getShardId(kvEntryCount());
        bool updatePrepaidTime = false;
        uint256 prepaidAmountSaved = 0;
        uint256 reward = 0;
        if (_shardId < lastShardIdx) {
            reward = _paymentIn(STORAGE_COST << SHARD_ENTRY_BITS, info.lastMineTime, _minedTs);
        } else if (_shardId == lastShardIdx) {
            reward = _paymentIn(STORAGE_COST * (kvEntryCount() % (1 << SHARD_ENTRY_BITS)), info.lastMineTime, _minedTs);
            // Additional prepaid for the last shard
            if ($._prepaidLastMineTime < _minedTs) {
                uint256 fullReward = _paymentIn(STORAGE_COST << SHARD_ENTRY_BITS, info.lastMineTime, _minedTs);
                uint256 prepaidAmountIn = _paymentIn($._prepaidAmount, $._prepaidLastMineTime, _minedTs);
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
    /// @param _minedTs     The mined block timestamp.
    /// @return The mining reward.
    function miningReward(uint256 _shardId, uint256 _minedTs) public view returns (uint256) {
        (,,, uint256 minerReward) = _miningReward(_shardId, _minedTs);
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
        StorageContractStorage storage $ = _getStorageContractStorage();
        if ($._enforceMinerRole && !hasRole(MINER_ROLE, _miner)) {
            revert StorageContract_MinerNotWhitelisted();
        }
        _mine(
            _blockNum, _shardId, _miner, _nonce, _encodedSamples, _masks, _randaoProof, _inclusiveProofs, _decodeProof
        );
    }

    /// @notice Set the nonce limit.
    function setNonceLimit(uint256 _nonceLimit) public onlyRole(DEFAULT_ADMIN_ROLE) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        $._nonceLimit = _nonceLimit;
    }

    /// @notice Set the prepaid amount.
    function setPrepaidAmount(uint256 _prepaidAmount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        $._prepaidAmount = _prepaidAmount;
    }

    /// @notice Set the treasury address.
    function setMinimumDiff(uint256 _minimumDiff) public onlyRole(DEFAULT_ADMIN_ROLE) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        $._minimumDiff = _minimumDiff;
    }

    /// @notice Enable or disable the MINER_ROLE check.
    /// @param _enforceMinerRole Boolean to enable or disable the check.
    function setEnforceMinerRole(bool _enforceMinerRole) public onlyRole(DEFAULT_ADMIN_ROLE) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        $._enforceMinerRole = _enforceMinerRole;
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
        if (_blockNumber() - _blockNum > MAX_L1_MINING_DRIFT) {
            revert StorageContract_BlockNumberTooOld();
        }
        // To avoid stack too deep, we reuse the hash0 instead of using randao
        bytes32 hash0 = _getRandao(_blockNum, _randaoProof);
        // Query block timestamp
        uint256 mineTs = _getMinedTs(_randaoProof);

        {
            // Given a blockhash and a miner, we only allow sampling up to nonce limit times.
            StorageContractStorage storage $ = _getStorageContractStorage();
            if (_nonce >= $._nonceLimit) {
                revert StorageContract_NonceTooBig();
            }
        }

        // Check if the data matches the hash in metadata and obtain the solution hash.
        hash0 = keccak256(abi.encode(_miner, hash0, _nonce));
        hash0 = verifySamples(_shardId, hash0, _miner, _encodedSamples, _masks, _inclusiveProofs, _decodeProof);

        // Check difficulty
        uint256 diff = _calculateDiffAndInitHashSingleShard(_shardId, mineTs);
        uint256 required = uint256(2 ** 256 - 1) / diff;

        if (uint256(hash0) > required) {
            revert StorageContract_DifficultyNotMet();
        }

        _rewardMiner(_shardId, _miner, mineTs, diff);
    }

    /// @notice Withdraw treasury fund
    function withdraw(uint256 _amount) public {
        StorageContractStorage storage $ = _getStorageContractStorage();
        if ($._accPrepaidAmount < $._prepaidAmount + _amount) {
            revert StorageContract_NotEnoughPrepaidAmount();
        }

        $._accPrepaidAmount -= _amount;

        if (address(this).balance < _amount) {
            revert StorageContract_NotEnoughBalance();
        }

        payable($._treasury).transfer(_amount);
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

        if (bh == bytes32(0)) {
            revert StorageContract_FailedToObtainBlockhash();
        }

        return RandaoLib.verifyHeaderAndGetRandao(bh, _headerRlpBytes);
    }

    /// @notice Get the mined timestamp
    function _getMinedTs(bytes calldata _headerRlpBytes) internal pure returns (uint256) {
        return RandaoLib.getTimestampFromHeader(_headerRlpBytes);
    }

    /// @notice Get the shard id by kv entry count.
    function _getShardId(uint256 _kvEntryCount) internal view returns (uint256) {
        return _kvEntryCount > 0 ? (_kvEntryCount - 1) >> SHARD_ENTRY_BITS : 0;
    }

    /// @notice Return the minimumDiff
    function minimumDiff() public view returns (uint256) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        return $._minimumDiff;
    }

    /// @notice Return the prepaid amount.
    function prepaidAmount() public view returns (uint256) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        return $._prepaidAmount;
    }

    /// @notice Return the mining info
    function infos(uint256 _shardId) public view returns (uint256, uint256, uint256) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        return ($._infos[_shardId].lastMineTime, $._infos[_shardId].difficulty, $._infos[_shardId].blockMined);
    }

    /// @notice Set the mining info
    function setMiningInfo(uint256 _shardId, MiningLib.MiningInfo memory _info) internal {
        StorageContractStorage storage $ = _getStorageContractStorage();
        $._infos[_shardId] = _info;
    }

    /// @notice Return the max nonce limit.
    function nonceLimit() public view returns (uint256) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        return $._nonceLimit;
    }

    /// @notice Return the treasury address.
    function treasury() public view returns (address) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        return $._treasury;
    }

    /// @notice Return the prepaid last mine time.
    function prepaidLastMineTime() public view returns (uint256) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        return $._prepaidLastMineTime;
    }

    /// @notice Return the accumulated prepaid amount.
    function accPrepaidAmount() public view returns (uint256) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        return $._accPrepaidAmount;
    }

    /// @notice Return enforce miner role.
    function enforceMinerRole() public view returns (bool) {
        StorageContractStorage storage $ = _getStorageContractStorage();
        return $._enforceMinerRole;
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
