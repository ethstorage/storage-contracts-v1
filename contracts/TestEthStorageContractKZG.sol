// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract2.sol";

contract TestEthStorageContractKZG is EthStorageContract2 {

    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _prepaidAmount,
        uint256 _nonceLimit
    ) EthStorageContract2(_config, _startTime, _storageCost, _dcfFactor, _prepaidAmount, _nonceLimit) {}

    // a test only method to upload multiple blobs in one tx
    function putBlobs(bytes32[] memory keys) public payable {
        for (uint256 i = 0; i < keys.length; i++) {
            putBlob(keys[i], i, maxKvSize);
        }
    }

    function putBlobs(uint256 num) public payable {
        for (uint256 i = 0; i < num; i++) {
            bytes32 key = keccak256(abi.encode(block.number, i));
            putBlob(key, 0, maxKvSize);
        }
    }
}
