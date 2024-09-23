// SPDX License Identifier: MIT
pragma solidity ^0.8.0;

import "../StorageContract.sol";

contract TestStorageContract is StorageContract {
    constructor(Config memory _config, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor)
        StorageContract(_config, _startTime, _storageCost, _dcfFactor)
    {}

    function initialize(
        uint256 _minimumDiff,
        uint256 _prepaidAmount,
        uint256 _nonceLimit,
        address _treasury,
        address _owner
    ) public payable initializer {
        __init_storage(_minimumDiff, _prepaidAmount, _nonceLimit, _treasury, _owner);
    }

    function verifySamples(
        uint256 _startShardId,
        bytes32 _hash0,
        address _miner,
        bytes32[] memory _encodedSamples,
        uint256[] memory _masks,
        bytes[] calldata _inclusiveProofs,
        bytes[] calldata _decodeProof
    ) public pure override returns (bytes32) {
        return bytes32(0);
    }

    function setKvEntryCount(uint40 _kvEntryCount) public {
        kvEntryCount = _kvEntryCount;
    }

    function paymentIn(uint256 _x, uint256 _fromTs, uint256 _toTs) public view returns (uint256) {
        return _paymentIn(_x, _fromTs, _toTs);
    }

    function miningRewards(uint256 _shardId, uint256 _minedTs) public view returns (bool, uint256, uint256) {
        return _miningReward(_shardId, _minedTs);
    }

    function rewardMiner(uint256 _shardId, address _miner, uint256 _minedTs, uint256 _diff) public {
        return _rewardMiner(_shardId, _miner, _minedTs, _diff);
    }

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
    ) internal override {
        uint256 mineTs = _getMinedTs(_blockNum);
        _rewardMiner(_shardId, _miner, mineTs, 1);
    }
}
