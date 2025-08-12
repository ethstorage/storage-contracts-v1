// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../EthStorageContractM2L2.sol";

contract TestEthStorageContractM2L2 is EthStorageContractM2L2 {
    constructor() {}

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
