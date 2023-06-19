// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract.sol";

contract BlobHashGetterFactory {
    constructor() payable {
        bytes memory code = hex"6000354960005260206000F3";
        uint256 size = code.length;
        assembly {
            return(add(code, 0x020), size)
        }
    }
}

library BlobHashGetter {
    function getBlobHash(address getter, uint256 idx) internal view returns (bytes32) {
        bool success;
        bytes32 blobHash;
        assembly {
            mstore(0x0, idx)
            success := staticcall(gas(), getter, 0x0, 0x20, 0x0, 0x20)
            blobHash := mload(0x0)
        }
        require(success, "failed to get blob hash");
        return blobHash;
    }
}

contract TestEthStorageContractKZG is EthStorageContract {
    address public hashGetter;

    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury,
        uint256 _prepaidAmount
    ) EthStorageContract(_config, _startTime, _storageCost, _dcfFactor, _nonceLimit, _treasury, _prepaidAmount) {
        hashGetter = address(new BlobHashGetterFactory());
    }

    // a test only method to upload multiple blobs in one tx
    // note that the key is randomly given and the length of the data may not correct
    function putBlobs(uint256 blobLen) public payable { 
        for (uint256 i = 0; i < blobLen; i++) { 
            bytes32 key = keccak256(abi.encode(msg.sender, block.timestamp, i));
            putBlob(key, i, maxKvSize);
        }
    }

    function putBlob(bytes32 key, uint256 blobIdx, uint256 length) public payable override {
        bytes32 dataHash = BlobHashGetter.getBlobHash(hashGetter, blobIdx);
        uint256 kvIdx = _putInternal(key, dataHash, length);
        emit PutBlob(kvIdx, length, dataHash);
    }

    function getHashByKvIdx(uint256 kvIdx) public view returns (bytes32) {
        return kvMap[idxMap[kvIdx]].hash;
    }

    function verifySamples(
        uint256 startShardId,
        bytes32 hash0,
        address miner,
        bytes32[] memory encodedSamples,
        bytes[] calldata inclusiveProofs
    ) public view returns (bytes32) {
        return _verifySamples(startShardId, hash0, miner, encodedSamples, inclusiveProofs);
    }
}
