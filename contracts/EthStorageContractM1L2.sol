// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./EthStorageContractM1.sol";
import "./L2Base.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:proxied
/// @title EthStorageContractM1L2
/// @notice EthStorage contract that will be deployed on L2, and uses mode 1 zk proof.
contract EthStorageContractM1L2 is Initializable, EthStorageContractM1, L2Base {
    /// @notice Constructs the EthStorageContractM1L2 contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the EthStorageContractM1L2 contract.
    function initialize(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _minimumDiff,
        uint256 _prepaidAmount,
        uint256 _nonceLimit,
        address _treasury,
        address _admin,
        uint256 _updateLimit
    ) public initializer {
        // Initialize parent contracts
        EthStorageContractM1.initialize(
            _config, _startTime, _storageCost, _dcfFactor, _minimumDiff, _prepaidAmount, _nonceLimit, _treasury, _admin
        );
        __L2Base_init(_updateLimit);
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
