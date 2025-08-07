// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "./TestEthStorageContractM2L2.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SoulGasToken {
    function chargeFromOrigin(uint256 _amount) external pure returns (uint256) {
        return _amount;
    }
}

contract EthStorageContractL2Test is Test {
    uint256 constant STORAGE_COST = 0;
    uint256 constant SHARD_SIZE_BITS = 19;
    uint256 constant MAX_KV_SIZE = 17;
    uint256 constant PREPAID_AMOUNT = 0;
    uint256 constant UPDATE_LIMIT = 16;

    TestEthStorageContractM2L2 storageContract;
    address owner = address(0x1);

    function setUp() public {
        TestEthStorageContractM2L2 imp = new TestEthStorageContractM2L2(
            StorageContract.Config(MAX_KV_SIZE, SHARD_SIZE_BITS, 2, 0, 0, 0), 0, STORAGE_COST, 0, UPDATE_LIMIT
        );
        bytes memory data = abi.encodeWithSelector(
            storageContract.initialize.selector, 0, PREPAID_AMOUNT, 0, address(0x1), address(0x1)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(imp), owner, data);

        storageContract = TestEthStorageContractM2L2(address(proxy));
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
        assertEq(storageContract.getBlockLastUpdate(), 0);

        // Append 1 new key-values, leaving 5 as updating
        keys[0] = bytes32(uint256(10));
        storageContract.putBlobs(keys, blobIdxs, lengths);
        assertEq(storageContract.getBlobsUpdated(), 5);
        assertEq(storageContract.getBlockLastUpdate(), 10000);

        // Update all 6
        storageContract.putBlobs(keys, blobIdxs, lengths);
        assertEq(storageContract.getBlobsUpdated(), 11);

        // Update all 6 again, exceeds UPDATE_LIMIT = 16
        vm.expectRevert("EthStorageContractM2L2: exceeds update rate limit");
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
        vm.expectRevert("EthStorageContractM2L2: exceeds update rate limit");
        storageContract.putBlobs(keys, blobIdxs, lengths);
    }

    function testSGTPayment() public {
        TestEthStorageContractM2L2 imp = new TestEthStorageContractM2L2(
            StorageContract.Config(MAX_KV_SIZE, SHARD_SIZE_BITS, 2, 0, 0, 0),
            block.timestamp,
            1500000000000000,
            0,
            UPDATE_LIMIT
        );
        bytes memory data = abi.encodeWithSelector(
            storageContract.initialize.selector, 0, PREPAID_AMOUNT, 0, address(0x1), address(0x1)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(imp), owner, data);

        TestEthStorageContractM2L2 l2Contract = TestEthStorageContractM2L2(address(proxy));

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

        vm.expectRevert("EthStorageContractM2L2: not enough batch payment");
        l2Contract.putBlobs{value: 1500000000000000 * 5}(keys, blobIdxs, lengths);

        l2Contract.putBlobs{value: 1500000000000000 * 6}(keys, blobIdxs, lengths);

        SoulGasToken sgt = new SoulGasToken();
        vm.prank(owner);
        l2Contract.setSoulGasToken(address(sgt));

        for (uint256 i = 0; i < size; i++) {
            keys[i] = bytes32(uint256(i + 6));
            hashes[i] = bytes32(uint256((i + 1) << 64));
            blobIdxs[i] = i;
            lengths[i] = 10 + i * 10;
        }
        vm.blobhashes(hashes);
        l2Contract.putBlobs(keys, blobIdxs, lengths);
    }
}
