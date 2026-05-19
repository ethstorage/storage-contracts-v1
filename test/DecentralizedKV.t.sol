// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TestDecentralizedKV} from "./mocks/TestDecentralizedKV.sol";
import {DecentralizedKV} from "../contracts/DecentralizedKV.sol";

contract DecentralizedKVTest is Test {
    bytes32 constant KEY1 = bytes32(uint256(1));
    bytes32 constant KEY2 = bytes32(uint256(2));
    bytes32 constant KEY3 = bytes32(uint256(3));
    bytes4 constant ERR_NOT_ENOUGH = bytes4(keccak256("DecentralizedKV_NotEnoughBatchPayment()"));
    DecentralizedKV.DecodeType constant RAW_DATA = DecentralizedKV.DecodeType.RawData;

    address internal addr0;
    address internal addr1;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public {
        addr0 = makeAddr("addr0");
        addr1 = makeAddr("addr1");
        vm.deal(addr0, 100 ether);
        vm.deal(addr1, 100 ether);
    }

    function _deploy(uint256 storageCost, uint256 dcfFactor) internal returns (TestDecentralizedKV kv) {
        kv = new TestDecentralizedKV(1024, 0, storageCost, dcfFactor);
        kv.initialize();
    }

    function testPutGetRemove() public {
        TestDecentralizedKV kv = _deploy(0, 0);

        kv.put(KEY1, hex"11223344");
        assertEq(kv.get(KEY1, RAW_DATA, 0, 4), hex"11223344");
        assertEq(kv.get(KEY1, RAW_DATA, 1, 2), hex"2233");
        assertEq(kv.get(KEY1, RAW_DATA, 2, 3), hex"3344");

        kv.remove(KEY1);
        assertFalse(kv.exist(KEY1));
        assertEq(kv.get(KEY1, RAW_DATA, 0, 4).length, 0);
    }

    function testPutGetReplacement() public {
        TestDecentralizedKV kv = _deploy(0, 0);

        kv.put(KEY1, hex"11223344");
        assertEq(kv.get(KEY1, RAW_DATA, 0, 4), hex"11223344");

        kv.put(KEY1, hex"772233445566");
        assertEq(kv.get(KEY1, RAW_DATA, 0, 4), hex"77223344");
        assertEq(kv.get(KEY1, RAW_DATA, 0, 6), hex"772233445566");

        kv.put(KEY1, hex"8899");
        assertEq(kv.get(KEY1, RAW_DATA, 0, 4), hex"8899");

        kv.put(KEY1, hex"");
        assertEq(kv.get(KEY1, RAW_DATA, 0, 4).length, 0);
    }

    function testPutRemoveWithPaymentHalfDiscountPerSecond() public {
        // 1 ether cost with 0.5 discount per second
        TestDecentralizedKV kv = _deploy(1 ether, 170141183460469231731687303715884105728);

        assertEq(kv.upfrontPayment(), 1 ether);

        vm.expectRevert(ERR_NOT_ENOUGH);
        kv.put(KEY1, hex"11223344");

        vm.expectRevert(ERR_NOT_ENOUGH);
        kv.put{value: 0.9 ether}(KEY1, hex"11223344");

        kv.put{value: 1 ether}(KEY1, hex"11223344");

        kv.setTimestamp(1);
        assertEq(kv.upfrontPayment(), 0.5 ether);
        kv.put{value: 0.5 ether}(KEY2, hex"33445566");

        kv.setTimestamp(4);
        assertEq(kv.upfrontPayment(), 0.0625 ether);
        kv.put{value: 0.0625 ether}(KEY3, hex"778899");

        address payable wallet = payable(makeAddr("wallet"));
        uint256 beforeBal = wallet.balance;

        kv.removeTo(KEY1, wallet);
        assertEq(wallet.balance - beforeBal, 0.0625 ether);
        assertFalse(kv.exist(KEY1));
        assertEq(kv.get(KEY1, RAW_DATA, 0, 4).length, 0);
    }

    function testPutWithPaymentYearlyDiscount() public {
        // 1 ether cost with 0.9 discount per second
        TestDecentralizedKV kv = _deploy(1 ether, 340282365784068676928457747575078800565);

        assertEq(kv.upfrontPayment(), 1 ether);

        vm.expectRevert(ERR_NOT_ENOUGH);
        kv.put(KEY1, hex"11223344");

        vm.expectRevert(ERR_NOT_ENOUGH);
        kv.put{value: 0.9 ether}(KEY1, hex"11223344");

        kv.put{value: 1 ether}(KEY1, hex"11223344");

        kv.setTimestamp(1);
        assertEq(kv.upfrontPayment(), 999999996659039970);

        kv.setTimestamp(3600 * 24 * 365);
        assertEq(kv.upfrontPayment(), 0.9 ether);
    }

    function testRemovesMultiUser() public {
        TestDecentralizedKV kv = _deploy(0, 0);

        for (uint256 i; i < 10; ++i) {
            vm.prank(addr0);
            kv.put(bytes32(i), abi.encodePacked(bytes32(i)));
        }
        for (uint256 i; i < 5; ++i) {
            vm.prank(addr1);
            kv.put(bytes32(i), abi.encodePacked(bytes32(i + 100)));
        }
        for (uint256 i; i < 10; ++i) {
            vm.prank(addr0);
            bytes memory got = kv.get(bytes32(i), RAW_DATA, 0, 1024);
            assertEq(got, abi.encodePacked(bytes32(i)));
        }
        for (uint256 i; i < 5; ++i) {
            vm.prank(addr1);
            bytes memory got = kv.get(bytes32(i), RAW_DATA, 0, 1024);
            assertEq(got, abi.encodePacked(bytes32(i + 100)));
        }

        vm.prank(addr0);
        kv.remove(bytes32(uint256(5)));
        vm.prank(addr1);
        kv.remove(bytes32(uint256(0)));
        vm.prank(addr0);
        kv.remove(bytes32(uint256(1)));
        vm.prank(addr1);
        kv.remove(bytes32(uint256(2)));
        vm.prank(addr0);
        kv.remove(bytes32(uint256(6)));

        for (uint256 i; i < 10; ++i) {
            vm.prank(addr0);
            bytes memory got = kv.get(bytes32(i), RAW_DATA, 0, 1024);
            if (i == 1 || i == 5 || i == 6) {
                assertEq(got.length, 0);
            } else {
                assertEq(got, abi.encodePacked(bytes32(i)));
            }
        }

        for (uint256 i; i < 5; ++i) {
            vm.prank(addr1);
            bytes memory got = kv.get(bytes32(i), RAW_DATA, 0, 1024);
            if (i == 0 || i == 2) {
                assertEq(got.length, 0);
            } else {
                assertEq(got, abi.encodePacked(bytes32(i + 100)));
            }
        }
    }

    function testGetStorageKeyEquals() public {
        TestDecentralizedKV kv = _deploy(0, 0);

        /// forge-lint: disable-next-line(asm-keccak256)
        bytes32 k = keccak256("demo-key");
        bytes32 a = kv.storageKeyAsm(k);
        bytes32 b = kv.storageKeyAbi(k);
        assertEq(a, b, "storageKeyAsm != storageKeyAbi");
    }
}
