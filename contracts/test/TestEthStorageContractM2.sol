// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../EthStorageContractM2.sol";

contract TestEthStorageContractM2 is EthStorageContractM2 {
    constructor() EthStorageContractM2() {}

    function initializeTest(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _minimumDiff,
        uint256 _prepaidAmount,
        uint256 _nonceLimit,
        address _treasury,
        address _admin
    ) public {
        initialize(
            _config, _startTime, _storageCost, _dcfFactor, _minimumDiff, _prepaidAmount, _nonceLimit, _treasury, _admin
        );
    }

    // a test only method to upload multiple blobs in one tx
    function putBlobs(bytes32[] memory keys) public payable {
        for (uint256 i = 0; i < keys.length; i++) {
            putBlob(keys[i], i, MAX_KV_SIZE);
        }
    }

    function putBlobs(uint256 num) public payable {
        for (uint256 i = 0; i < num; i++) {
            bytes32 key = keccak256(abi.encode(block.number, i));
            putBlob(key, 0, MAX_KV_SIZE);
        }
    }
}
