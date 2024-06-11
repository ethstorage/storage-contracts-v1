// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract2.sol";

interface IL1Block {
    function blockHash(uint256 _historyNumber) external view returns (bytes32);

    function number() external view returns (uint64);

    function timestamp() external view returns (uint64);
}

contract EthStorageContractL2 is EthStorageContract2 {
    IL1Block public constant l1Block = IL1Block(0x4200000000000000000000000000000000000015);
    uint16 public constant maxL2MiningDrift = 64 * 6;

    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor
    ) EthStorageContract2(_config, _startTime, _storageCost, _dcfFactor) {}

    function getRandao(uint256 l1BlockNumber, bytes calldata headerRlpBytes) internal view returns (bytes32) {
        bytes32 bh = l1Block.blockHash(l1BlockNumber);
        require(bh != bytes32(0), "failed to obtain blockhash");

        return RandaoLib.verifyHeaderAndGetRandao(bh, headerRlpBytes);
    }

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
    ) internal override {
        // Obtain the blockhash of the block number of recent blocks
        require(l1Block.number() - blockNumber <= maxL1MiningDrift, "block number too old");
        // To avoid stack too deep, we resue the hash0 instead of using randao

        bytes32 hash0 = getRandao(blockNumber, randaoProof);
        // Estimate block timestamp
        uint256 mineTs = l1Block.timestamp() - (l1Block.number() - blockNumber) * 12;

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
}
