// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../EthStorageContractM2L2.sol";

contract TestEthStorageContractM2L2 is EthStorageContractM2L2 {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _updateLimit
    ) EthStorageContractM2L2(_config, _startTime, _storageCost, _dcfFactor, _updateLimit) {}

    /// @notice Initialize the contract
    function initialize(
        uint256 _minimumDiff,
        uint256 _prepaidAmount,
        uint256 _nonceLimit,
        address _treasury,
        address _owner
    ) public payable override initializer {
        super.initialize(_minimumDiff, _prepaidAmount, _nonceLimit, _treasury, _owner);
    }

    /// @notice Get the number of blobs updated within the current block.
    function getBlobsUpdated() public view returns (uint256) {
        return updateState() & type(uint32).max;
    }

    /// @notice Get the block number of the last update.
    function getBlockLastUpdate() public view returns (uint256) {
        return updateState() >> 32;
    }

    function _blockNumber() internal view virtual override returns (uint256) {
        return block.number;
    }

    /// @notice Get the current block timestamp
    function _blockTs() internal view virtual override returns (uint256) {
        return block.timestamp;
    }
}
