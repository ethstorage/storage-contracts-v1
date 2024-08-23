// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../libraries/MiningLib.sol";
import "forge-std/Test.sol";

contract MiningLibTest is Test {
    uint256 constant RANDOM_CHECKS = 2;
    uint256 constant CUT_OFF = 7200;
    uint256 constant DIFF_ADJ_DIVISOR = 32;
    uint256 constant MIN_DIFF = 9437184;

    MiningLib.MiningInfo info;

    function test_CheckDiff() public {
        address miner = 0x471977571aD818379E2b6CC37792a5EaC85FdE22;
        uint256 minedTs = 1724243184;
        uint256 lastMinedTime = 1724242128;
        uint256 lastDiff = 71922272;
        uint256 nonce = 870911;
        bytes32 randao = 0xd2c65935c5fc39a515a0282c03ccd8a7879264ae01f697c89da2b0c6e3fa296d;
        bytes32[] memory encodedSamples = new bytes32[](2);
        encodedSamples[0] = 0x0c1e76b42ca04b0b349ed3e6300cc8f67bdfa16f35315acae9d53849935eb727;
        encodedSamples[1] = 0x2a0b69a3663ae7ad5cf2d9da8bdfff961f5631243f5bdc337e1fd20fad5f3e2d;

        checkDiff(miner, minedTs, lastMinedTime, lastDiff, nonce, randao, encodedSamples);
    }

    function checkDiff(
        address _miner,
        uint256 _minedTs,
        uint256 _lastMinedTime,
        uint256 _lastDiff,
        uint256 _nonce,
        bytes32 _randao,
        bytes32[] memory _encodedSamples
    ) public {
        bytes32 hash0 = keccak256(abi.encode(_miner, _randao, _nonce));
        for (uint256 i = 0; i < RANDOM_CHECKS; i++) {
            hash0 = keccak256(abi.encode(hash0, _encodedSamples[i]));
        }
        info = MiningLib.MiningInfo(_lastMinedTime, _lastDiff, 0);
        uint256 diff = MiningLib.expectedDiff(info, _minedTs, CUT_OFF, DIFF_ADJ_DIVISOR, MIN_DIFF);
        uint256 required = uint256(2 ** 256 - 1) / diff;
        require(uint256(hash0) <= required, "diff not match");
    }
}
