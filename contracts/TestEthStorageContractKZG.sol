// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract.sol";

contract TestEthStorageContractKZG is EthStorageContract {
    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury,
        uint256 _prepaidAmount
    ) EthStorageContract(_config, _startTime, _storageCost, _dcfFactor, _nonceLimit, _treasury, _prepaidAmount) {}

    // a test only method to upload multiple blobs in one tx
    function putBlobs(bytes32[] memory keys) public payable {
        for (uint256 i = 0; i < keys.length; i++) {
            putBlob(keys[i], i, maxKvSize);
        }
    }

    function putHashes(bytes32[] memory hashes) public payable virtual {
        for (uint256 i = 0; i < hashes.length; i++) {
            uint256 kvIdx = _putInternal(hashes[i], hashes[i], maxKvSize);
            emit PutBlob(kvIdx, maxKvSize, hashes[i]);
        }
    }
}
