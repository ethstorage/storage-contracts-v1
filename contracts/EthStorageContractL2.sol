// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract2.sol";

interface IL1Block {
    function blockHash(uint256 _historyNumber) external view returns (bytes32);
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

    function _getRandao(uint256 l1BlockNumber, bytes calldata headerRlpBytes) internal view override returns (bytes32) {
        bytes32 bh = l1Block.blockHash(l1BlockNumber);
        require(bh != bytes32(0), "failed to obtain blockhash");

        return RandaoLib.verifyHeaderAndGetRandao(bh, headerRlpBytes);
    }

    function _getMaxMiningDrift() internal pure override returns (uint256) {
        return maxL2MiningDrift;
    }
}
