// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../EthStorageContractM2L2.sol";
// import "forge-std/Test.sol"; // will cause https://zpl.in/upgrades/error-004
// So we use the base contract directly
import "forge-std/Base.sol";

contract TestEthStorageContractM2L2 is EthStorageContractM2L2, CommonBase {
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

    function putBlobs(bytes32[] memory _keys, uint256[] memory _blobIdxs, uint256[] memory _lengths)
        public
        payable
        override
    {
        uint256 blobIndexesLength = _blobIdxs.length;
        if ((_keys.length != blobIndexesLength) || (_keys.length != _lengths.length)) {
            revert EthStorageContract_LengthMismatch();
        }

        bytes32[] memory dataHashes = new bytes32[](_blobIdxs.length);
        bytes32[] memory blobHashes = vm.getBlobhashes();
        for (uint256 i = 0; i < blobIndexesLength; i++) {
            dataHashes[i] = blobHashes[_blobIdxs[i]];
            if (dataHashes[i] == 0) {
                revert EthStorageContract_FailedToGetBlobHash();
            }
        }

        uint256[] memory kvIdxs = _putBatchInternal(_keys, dataHashes, _lengths);

        for (uint256 i = 0; i < blobIndexesLength; i++) {
            emit PutBlob(kvIdxs[i], _lengths[i], dataHashes[i]);
        }
    }
}
