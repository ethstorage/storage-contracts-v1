// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EthStorageContractM2} from "../../contracts/EthStorageContractM2.sol";

contract TestEthStorageContractM2 is EthStorageContractM2 {
    constructor(Config memory _config, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor)
        EthStorageContractM2(_config, _startTime, _storageCost, _dcfFactor)
    {}

    // a test only method to upload multiple blobs in one tx
    function putBlobs(bytes32[] memory keys) public payable {
        for (uint256 i = 0; i < keys.length; i++) {
            putBlob(keys[i], i, MAX_KV_SIZE);
        }
    }

    function putBlobs(uint256 num) public payable {
        for (uint256 i = 0; i < num; i++) {
            /// forge-lint: disable-next-line(asm-keccak256)
            bytes32 key = keccak256(abi.encode(block.number, i));
            putBlob(key, 0, MAX_KV_SIZE);
        }
    }
}
