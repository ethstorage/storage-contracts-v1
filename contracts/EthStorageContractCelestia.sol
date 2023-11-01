// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract.sol";

contract EthStorageContractCelestia is EthStorageContract {
    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury,
        uint256 _prepaidAmount
    ) EthStorageContract(_config, _startTime, _storageCost, _dcfFactor, _nonceLimit, _treasury, _prepaidAmount) {}

    event PutBlobToCelestia(uint256 indexed kvIdx, uint256 indexed kvSize, bytes32 indexed dataHash, uint256 height);

    function putBlob(bytes32 key, bytes32 commitment, uint256 size, uint256 height) public payable {
        uint256 kvIdx = _putInternal(key, commitment, size);
        emit PutBlobToCelestia(kvIdx, size, commitment, height);
    }
}
