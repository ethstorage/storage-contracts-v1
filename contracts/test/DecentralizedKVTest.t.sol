// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {TestDecentralizedKV} from "./TestDecentralizedKV.sol";
import {Test} from "forge-std/Test.sol";

contract DecentralizedKVTest is Test {
    uint256 constant MAX_KV_SIZE = 17;
    uint256 constant STORAGE_COST = 10000000;
    uint256 constant SHARD_SIZE_BITS = 19;
    uint256 constant PREPAID_AMOUNT = 2 * STORAGE_COST;
    TestDecentralizedKV decentralizedKv;

    function setUp() public {
        decentralizedKv = new TestDecentralizedKV(MAX_KV_SIZE, 0, STORAGE_COST, 340282366367469178095360967382638002176);
        decentralizedKv.initialize();
    }

    function test_getStorageKeyEquals() public view {
        bytes32 k = keccak256("demo-key");
        bytes32 a = decentralizedKv.storageKeyAsm(k);
        bytes32 b = decentralizedKv.storageKeyAbi(k);
        assertEq(a, b, "storageKeyAsm != storageKeyAbi");
    }
}
