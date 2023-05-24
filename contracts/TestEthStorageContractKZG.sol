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

    function put(bytes32 key) public payable {
        bytes32 dataHash = BlobHashGetter.getBlobHash(hashGetter, 0);
        uint256 kvIdx = _putInternal(key, dataHash, 1 << 17);
        emit PutBlob(kvIdx, 1 << 17, dataHash);
    }

}
