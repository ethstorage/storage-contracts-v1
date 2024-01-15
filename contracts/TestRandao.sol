// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./RandaoLib.sol";

contract TestRandao {
    function verifyHeaderAndGetRandao(bytes32 headerHash, bytes memory headerRlpBytes) public pure returns (bytes32) {
        return RandaoLib.verifyHeaderAndGetRandao(headerHash, headerRlpBytes);
    }

    function verifyHistoricalRandao(uint256 blockNumber, bytes memory proof) public view returns (bytes32) {
        return RandaoLib.verifyHeaderAndGetRandao(blockNumber, proof);
    }
}