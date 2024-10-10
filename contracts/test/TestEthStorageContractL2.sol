// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../EthStorageContractL2.sol";

contract TestEthStorageContractL2 is EthStorageContractL2 {
    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _updateLimit
    ) EthStorageContractL2(_config, _startTime, _storageCost, _dcfFactor, _updateLimit) {}

    /// @notice Get the number of blobs updated within the current block.
    function getBlobsUpdated() public view returns (uint256) {
        return updateState & type(uint32).max;
    }

    /// @notice Get the block number of the last update.
    function getBlockLastUpdate() public view returns (uint256) {
        return updateState >> 32;
    }

    function _blockNumber() internal view virtual override returns (uint256) {
        return block.number;
    }

    /// @notice Get the current block timestamp
    function _blockTs() internal view virtual override returns (uint256) {
        return block.timestamp;
    }
}
