// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./EthStorageContractM1.sol";
import "./L2Base.sol";

/// @custom:proxied
/// @title EthStorageContractM1L2
/// @notice EthStorage contract that will be deployed on L2, and uses mode 1 zk proof.
contract EthStorageContractM1L2 is EthStorageContractM1, L2Base {
    /// @notice Constructs the EthStorageContractM1L2 contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _updateLimit
    ) EthStorageContractM1(_config, _startTime, _storageCost, _dcfFactor) L2Base(_updateLimit) {}

    /// @notice Initialize the contract.
    function initialize(
        uint256 _minimumDiff,
        uint256 _prepaidAmount,
        uint256 _nonceLimit,
        address _treasury,
        address _admin
    ) public payable override initializer {
        super.initialize(_minimumDiff, _prepaidAmount, _nonceLimit, _treasury, _admin);
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
    function _blockNumber() internal view override(StorageContract, L2Base) returns (uint256) {
        return L2Base._blockNumber();
    }

    /// @notice Get the current block timestamp
    function _blockTs() internal view override(StorageContract, L2Base) returns (uint256) {
        return L2Base._blockTs();
    }

    /// @notice Get the randao value from the L1 blockhash.
    function _getRandao(uint256 _l1BlockNumber, bytes calldata _headerRlpBytes)
        internal
        view
        override(StorageContract, L2Base)
        returns (bytes32)
    {
        return L2Base._getRandao(_l1BlockNumber, _headerRlpBytes);
    }

    /// @notice Check if the key-values being updated exceed the limit per block.
    function _checkUpdateLimit(uint256 _updateSize) internal override(DecentralizedKV, L2Base) {
        L2Base._checkUpdateLimit(_updateSize);
    }

    /// @notice Set the soul gas token address for the contract.
    function setSoulGasToken(address _soulGasToken) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setSoulGasToken(_soulGasToken);
    }
}
