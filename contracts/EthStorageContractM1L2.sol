// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./EthStorageContractM1.sol";

/// @title IL1Block
/// @notice Interface for L1Block contract.
interface IL1Block {
    /// @notice Get the blockhash of an L1 history block number.
    /// @param _historyNumber The L1 history block number.
    /// @return The blockhash of the L1 history block number.
    function blockHash(uint256 _historyNumber) external view returns (bytes32);

    /// @notice Get the current L1 block number.
    /// @return The current L1 block number.
    function number() external view returns (uint64);

    /// @notice Get the current L1 block timestamp.
    /// @return The current L1 block timestamp.
    function timestamp() external view returns (uint64);
}

/// @title ISoulGasToken
/// @notice Interface for the SoulGasToken contract.
interface ISoulGasToken {
    function chargeFromOrigin(uint256 _amount) external returns (uint256);
}

/// @custom:proxied
/// @title EthStorageContractM1L2
/// @notice EthStorage contract that will be deployed on L2, and uses L1Block contract to mine.
contract EthStorageContractM1L2 is EthStorageContractM1 {
    /// @notice The precompile contract address for L1Block.
    IL1Block internal constant L1_BLOCK = IL1Block(0x4200000000000000000000000000000000000015);

    /// @notice The mask to extract `blockLastUpdate`
    uint256 internal constant MASK = ~uint256(0) ^ type(uint32).max;

    /// @notice The rate limit to update blobs per block
    uint256 internal immutable UPDATE_LIMIT;

    /// @notice A slot to store both `blockLastUpdate` (left 224) and `blobsUpdated` (right 32)
    uint256 internal updateState;

    /// @notice The address of the soul gas token.
    address public soulGasToken;

    /// @notice Constructs the EthStorageContractM1L2 contract.
    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _updateLimit
    ) EthStorageContractM1(_config, _startTime, _storageCost, _dcfFactor) {
        UPDATE_LIMIT = _updateLimit;
    }

    /// @notice Set the soul gas token address for the contract.
    function setSoulGasToken(address _soulGasToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        soulGasToken = _soulGasToken;
    }

    /// @inheritdoc StorageContract
    function _checkAppend(uint256 _batchSize) internal virtual override {
        uint256 kvEntryCountPrev = kvEntryCount - _batchSize; // kvEntryCount already increased
        uint256 totalPayment = _upfrontPaymentInBatch(kvEntryCountPrev, _batchSize);
        uint256 sgtCharged = 0;
        if (soulGasToken != address(0)) {
            sgtCharged = ISoulGasToken(soulGasToken).chargeFromOrigin(totalPayment);
        }
        require(msg.value >= totalPayment - sgtCharged, "EthStorageContractM1L2: not enough batch payment");

        uint256 shardId = _getShardId(kvEntryCount); // shard id after the batch
        if (shardId > _getShardId(kvEntryCountPrev)) {
            // Open a new shard and mark the shard is ready to mine.
            infos[shardId].lastMineTime = _blockTs();
        }
    }

    /// @notice Get the current block number
    function _blockNumber() internal view virtual override returns (uint256) {
        return L1_BLOCK.number();
    }

    /// @notice Get the current block timestamp
    function _blockTs() internal view virtual override returns (uint256) {
        return L1_BLOCK.timestamp();
    }

    /// @notice Get the randao value from the L1 blockhash.
    function _getRandao(uint256 _l1BlockNumber, bytes calldata _headerRlpBytes)
        internal
        view
        override
        returns (bytes32)
    {
        bytes32 bh = L1_BLOCK.blockHash(_l1BlockNumber);
        require(bh != bytes32(0), "EthStorageContractM1L2: failed to obtain blockhash");
        return RandaoLib.verifyHeaderAndGetRandao(bh, _headerRlpBytes);
    }

    /// @notice Check if the key-values being updated exceed the limit per block.
    function _checkUpdateLimit(uint256 _updateSize) internal override {
        uint256 blobsUpdated = updateState & MASK == block.number << 32 ? updateState & type(uint32).max : 0;
        require(blobsUpdated + _updateSize <= UPDATE_LIMIT, "EthStorageContractM1L2: exceeds update rate limit");
        updateState = block.number << 32 | (blobsUpdated + _updateSize);
    }

    /// @notice Getter for UPDATE_LIMIT
    function getUpdateLimit() public view returns (uint256) {
        return UPDATE_LIMIT;
    }
}
