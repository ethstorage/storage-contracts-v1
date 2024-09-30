// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./TestEthStorageContractL2.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract EthStorageContractL2Test is Test {
    uint256 constant STORAGE_COST = 0;
    uint256 constant SHARD_SIZE_BITS = 19;
    uint256 constant MAX_KV_SIZE = 17;
    uint256 constant PREPAID_AMOUNT = 0;
    uint256 constant UPDATE_LIMIT = 16;

    TestEthStorageContractL2 storageContract;
    address owner = address(0x1);

    function setUp() public {
        TestEthStorageContractL2 imp = new TestEthStorageContractL2(
            StorageContract.Config(MAX_KV_SIZE, SHARD_SIZE_BITS, 2, 0, 0, 0), 0, STORAGE_COST, 0, UPDATE_LIMIT
        );
        bytes memory data = abi.encodeWithSelector(
            storageContract.initialize.selector, 0, PREPAID_AMOUNT, 0, address(0x1), address(0x1)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(imp), owner, data);

        storageContract = TestEthStorageContractL2(address(proxy));
    }

    function testUpdateLimit() public {
        uint256 size = 6;
        bytes32[] memory hashes = new bytes32[](size);
        bytes32[] memory keys = new bytes32[](size);
        uint256[] memory blobIdxs = new uint256[](size);
        uint256[] memory lengths = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            keys[i] = bytes32(uint256(i));
            hashes[i] = bytes32(uint256((i + 1) << 64));
            blobIdxs[i] = i;
            lengths[i] = 10 + i * 10;
        }
        vm.blobhashes(hashes);
        vm.roll(10000);

        // No updates
        storageContract.putBlobs(keys, blobIdxs, lengths);
        assertEq(storageContract.getBlobsUpdated(), 0);
        assertEq(storageContract.getBlockLastUpdate(), 10000);

        // Append 1 new key-values, leaving 5 as updating
        keys[0] = bytes32(uint256(10));
        storageContract.putBlobs(keys, blobIdxs, lengths);
        assertEq(storageContract.getBlobsUpdated(), 5);
        assertEq(storageContract.getBlockLastUpdate(), 10000);

        // Update all 6
        storageContract.putBlobs(keys, blobIdxs, lengths);
        assertEq(storageContract.getBlobsUpdated(), 11);

        // Update all 6 again, exceeds UPDATE_LIMIT = 16
        vm.expectRevert("EthStorageContractL2: exceeds update rate limit");
        storageContract.putBlobs(keys, blobIdxs, lengths);
        assertEq(storageContract.getBlockLastUpdate(), 10000);

        vm.roll(block.number + 1);

        // Update all 6
        storageContract.putBlobs(keys, blobIdxs, lengths);
        assertEq(storageContract.getBlobsUpdated(), 6);
        assertEq(storageContract.getBlockLastUpdate(), 10001);

        // Update till exceeds UPDATE_LIMIT = 16
        storageContract.putBlobs(keys, blobIdxs, lengths);
        assertEq(storageContract.getBlobsUpdated(), 12);
        assertEq(storageContract.getBlockLastUpdate(), 10001);
        vm.expectRevert("EthStorageContractL2: exceeds update rate limit");
        storageContract.putBlobs(keys, blobIdxs, lengths);
    }
}
