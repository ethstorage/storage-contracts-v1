// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract2.sol";

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

/// @custom:proxied
/// @title EthStorageContractL2
/// @notice EthStorage contract that will be deployed on L2, and uses L1Block contract to mine.
contract EthStorageContractL2 is EthStorageContract2 {
    /// @notice The precompile contract address for L1Block.
    IL1Block internal constant L1_BLOCK = IL1Block(0x4200000000000000000000000000000000000015);

    /// @notice Constructs the EthStorageContractL2 contract.
    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor
    ) EthStorageContract2(_config, _startTime, _storageCost, _dcfFactor) {}

    /// @notice Get the randao value from the L1 blockhash.
    function _getRandao(uint256 _l1BlockNumber, bytes calldata _headerRlpBytes) internal view returns (bytes32) {
        bytes32 bh = L1_BLOCK.blockHash(_l1BlockNumber);
        require(bh != bytes32(0), "EthStorageContractL2: failed to obtain blockhash");

        return RandaoLib.verifyHeaderAndGetRandao(bh, _headerRlpBytes);
    }

    /// @notice We are still using L1 block number, timestamp, and blockhash to mine eventhough we are on L2.
    /// @param _blockNumber  L1 blocknumber.
    /// @param _shardId  Shard ID.
    /// @param _miner  Miner address.
    /// @param _nonce  Nonce.
    /// @param _encodedSamples  Encoded samples.
    /// @param _masks  Sample masks.
    /// @param _randaoProof  L1 block header RLP bytes.
    /// @param _inclusiveProofs  Sample inclusive proofs.
    /// @param _decodeProof  Mask decode proof.
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
    ) internal override {
        // Obtain the blockhash of the block number of recent blocks
        require(L1_BLOCK.number() - _blockNumber <= MAX_L1_MINING_DRIFT, "EthStorageContractL2: block number too old");
        // To avoid stack too deep, we resue the hash0 instead of using randao

        bytes32 hash0 = _getRandao(_blockNumber, _randaoProof);
        // Estimate block timestamp
        uint256 mineTs = L1_BLOCK.timestamp() - (L1_BLOCK.number() - _blockNumber) * 12;

        // Given a blockhash and a miner, we only allow sampling up to nonce limit times.
        require(_nonce < nonceLimit, "EthStorageContractL2: nonce too big");

        // Check if the data matches the hash in metadata and obtain the solution hash.
        hash0 = keccak256(abi.encode(_miner, hash0, _nonce));
        hash0 = verifySamples(_shardId, hash0, _miner, _encodedSamples, _masks, _inclusiveProofs, _decodeProof);

        // Check difficulty
        uint256 diff = _calculateDiffAndInitHashSingleShard(_shardId, mineTs);
        uint256 required = uint256(2 ** 256 - 1) / diff;
        require(uint256(hash0) <= required, "EthStorageContractL2: diff not match");

        _rewardMiner(_shardId, _miner, mineTs, diff);
    }
}
