// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./EthStorageContractM2.sol";
import "./L2Base.sol";

/// @custom:proxied
/// @title EthStorageContractM2L2
/// @notice EthStorage contract that will be deployed on L2, and uses mode 2 zk proof.
contract EthStorageContractM2L2 is EthStorageContractM2, L2Base {
    /// @notice Thrown when the payment is not enough.
    error EthStorageContractM2L2_NotEnoughPayment();

    /// @notice Constructs the EthStorageContractM2L2 contract.
    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _updateLimit
    ) EthStorageContractM2(_config, _startTime, _storageCost, _dcfFactor) L2Base(_updateLimit) {}

    /// @inheritdoc StorageContract
    function _checkAppend(uint256 _batchSize) internal virtual override {
        uint256 kvEntryCountPrev = kvEntryCount() - _batchSize; // kvEntryCount already increased
        uint256 totalPayment = _upfrontPaymentInBatch(kvEntryCountPrev, _batchSize);
        uint256 sgtCharged = 0;
        if (soulGasToken != address(0)) {
            sgtCharged = ISoulGasToken(soulGasToken).chargeFromOrigin(totalPayment);
        }

        if (msg.value < totalPayment - sgtCharged) {
            revert EthStorageContractM2L2_NotEnoughPayment();
        }

        uint256 shardId = _getShardId(kvEntryCount()); // shard id after the batch
        if (shardId > _getShardId(kvEntryCountPrev)) {
            // Open a new shard and mark the shard is ready to mine.
            (, uint256 difficulty, uint256 blockMined) = infos(shardId);
            setMiningInfo(
                shardId,
                MiningLib.MiningInfo({lastMineTime: _blockTs(), difficulty: difficulty, blockMined: blockMined})
            );
        }
    }

    /// @notice Get the current block number
    function _blockNumber() internal view virtual override(StorageContract, L2Base) returns (uint256) {
        return L2Base._blockNumber();
    }

    /// @notice Get the current block timestamp
    function _blockTs() internal view virtual override(StorageContract, L2Base) returns (uint256) {
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
