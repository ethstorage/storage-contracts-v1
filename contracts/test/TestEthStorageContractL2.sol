// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../EthStorageContractL2.sol";

contract TestEthStorageContractL2 is EthStorageContractL2 {
    constructor(Config memory _config, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor)
        EthStorageContractL2(_config, _startTime, _storageCost, _dcfFactor)
    {}

    function getBlobsUpdated() public view returns (uint256) {
        return blobsUpdated;
    }

    function getBlockLastUpdate() public view returns (uint256) {
        return blockLastUpdate;
    }

    function _blockNumber() internal view virtual override returns (uint256) {
        return block.number;
    }

    /// @notice Get the current block timestamp
    function _blockTs() internal view virtual override returns (uint256) {
        return block.timestamp;
    }
}
