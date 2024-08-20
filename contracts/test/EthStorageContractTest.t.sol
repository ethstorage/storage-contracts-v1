// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./TestEthStorageContract.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract EthStorageContractTest is Test {
    uint256 constant STORAGE_COST = 1000;
    uint256 constant SHARD_SIZE_BITS = 19;
    uint256 constant MAX_KV_SIZE = 17;
    uint256 constant PREPAID_AMOUNT = 2 * STORAGE_COST;

    TestEthStorageContract storageContract;
    address owner = address(0x1);

    function setUp() public {
        TestEthStorageContract imp = new TestEthStorageContract(
            StorageContract.Config(MAX_KV_SIZE, SHARD_SIZE_BITS, 2, 0, 0, 0), 0, STORAGE_COST, 0
        );
        bytes memory data = abi.encodeWithSelector(
            storageContract.initialize.selector, 0, PREPAID_AMOUNT, 0, address(0x1), address(0x1)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(imp), owner, data);

        storageContract = TestEthStorageContract(address(proxy));
    }

    function testPutBlob() public {
        bytes32 key = bytes32(uint256(0));
        uint256 blobIdx = 0;
        uint256 length = 10;

        uint256 insufficientCost = storageContract.upfrontPayment() - 1;

        // Expect the specific revert reason from _prepareAppend due to insufficient msg.value
        vm.expectRevert("StorageContract: not enough batch payment");
        storageContract.putBlob{value: insufficientCost}(key, blobIdx, length);

        // Enough storage cost
        uint256 sufficientCost = storageContract.upfrontPayment();
        storageContract.putBlob{value: sufficientCost}(key, blobIdx, length);

        assertEq(storageContract.kvEntryCount(), 1);
        assertEq(storageContract.hash(key), bytes32(uint256(1 << 8 * 8)));
        assertEq(storageContract.size(key), 10);

        // Appending a new key-value
        key = bytes32(uint256(1));
        length = 20;
        sufficientCost = storageContract.upfrontPayment();
        storageContract.putBlob{value: sufficientCost}(key, blobIdx, length);
        assertEq(storageContract.kvEntryCount(), 2);
        assertEq(storageContract.hash(key), bytes32(uint256(1 << 8 * 8)));
        assertEq(storageContract.size(key), 20);
    }

    function testPutBlobs() public {
        bytes32[] memory keys = new bytes32[](2);
        keys[0] = bytes32(uint256(0));
        keys[1] = bytes32(uint256(1));
        uint256[] memory blobIdxs = new uint256[](2);
        blobIdxs[0] = 0;
        blobIdxs[1] = 0;
        uint256[] memory lengths = new uint256[](2);
        lengths[0] = 10;
        lengths[1] = 20;

        uint256 insufficientCost = storageContract.upfrontPayment();

        // Expect the specific revert reason from _prepareBatchAppend due to insufficient msg.value
        vm.expectRevert("StorageContract: not enough batch payment");
        storageContract.putBlobs{value: insufficientCost}(keys, blobIdxs, lengths);

        // Enough storage cost
        uint256 sufficientCost = storageContract.upfrontPaymentInBatch(2);
        storageContract.putBlobs{value: sufficientCost}(keys, blobIdxs, lengths);

        assertEq(storageContract.kvEntryCount(), 2);
        assertEq(storageContract.hash(keys[0]), bytes32(uint256(1 << 8 * 8)));
        assertEq(storageContract.hash(keys[1]), bytes32(uint256(2 << 8 * 8)));
        assertEq(storageContract.size(keys[0]), 10);
        assertEq(storageContract.size(keys[1]), 20);

        // Still pass two keys, but only appending a new key-value
        lengths[0] = 30;
        keys[1] = bytes32(uint256(2));
        lengths[1] = 30;

        sufficientCost = storageContract.upfrontPayment();
        storageContract.putBlobs{value: sufficientCost}(keys, blobIdxs, lengths);
        assertEq(storageContract.kvEntryCount(), 3);
        assertEq(storageContract.hash(bytes32(uint256(0))), bytes32(uint256(1 << 8 * 8)));
        assertEq(storageContract.hash(bytes32(uint256(1))), bytes32(uint256(2 << 8 * 8)));
        assertEq(storageContract.hash(bytes32(uint256(2))), bytes32(uint256(2 << 8 * 8)));
        assertEq(storageContract.size(bytes32(uint256(0))), 30);
        assertEq(storageContract.size(bytes32(uint256(1))), 20);
        assertEq(storageContract.size(bytes32(uint256(2))), 30);
    }

    function testPutBlobsXshard() public {
        uint256 size = 6;
        bytes32[] memory keys = new bytes32[](size);
        uint256[] memory blobIdxs = new uint256[](size);
        uint256[] memory lengths = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            keys[i] = bytes32(uint256(i));
            blobIdxs[i] = i;
            lengths[i] = 10 + i*10;
        }
        
        uint256 sufficientCost = storageContract.upfrontPaymentInBatch(size);
        uint256 insufficientCost = sufficientCost - 1;
        
        // Expect the specific revert reason from _prepareBatchAppend due to insufficient msg.value
        vm.expectRevert("StorageContract: not enough batch payment");
        storageContract.putBlobs{value: insufficientCost}(keys, blobIdxs, lengths);

        // Enough storage cost
        storageContract.putBlobs{value: sufficientCost}(keys, blobIdxs, lengths);
        assertEq(storageContract.kvEntryCount(), size);
    }
}
