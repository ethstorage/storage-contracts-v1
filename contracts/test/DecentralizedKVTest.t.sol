// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./TestDecentralizedKV.sol";
import "forge-std/Test.sol";

contract DecentralizedKVTest is Test {
    uint256 constant MAX_KV_SIZE = 17;
    uint256 constant STORAGE_COST = 10000000;
    uint256 constant SHARD_SIZE_BITS = 19;
    uint256 constant PREPAID_AMOUNT = 2 * STORAGE_COST;
    TestDecentralizedKV decentralizedKV;

    function setUp() public {
        decentralizedKV = new TestDecentralizedKV(MAX_KV_SIZE, 0, STORAGE_COST, 340282366367469178095360967382638002176);
        decentralizedKV.initialize(vm.addr(1));
    }

    function testTransferOwnership() public {
        vm.expectRevert();
        vm.prank(address(vm.addr(2)));
        decentralizedKV.transferOwnership(vm.addr(2));

        vm.prank(address(vm.addr(1)));
        decentralizedKV.transferOwnership(vm.addr(2));
        assertEq(decentralizedKV.owner(), vm.addr(1));

        vm.prank(address(vm.addr(2)));
        decentralizedKV.acceptOwnership();
        assertEq(decentralizedKV.owner(), vm.addr(2));
    }
}
