// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./TestStorageContract.sol";
import "../StorageContract.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

contract StorageContractTest is Test {
    uint256 constant STORAGE_COST = 1000;
    uint256 constant SHARD_SIZE_BITS = 19;
    uint256 constant MAX_KV_SIZE = 17;
    uint256 constant PREPAID_AMOUNT = 2 * STORAGE_COST;
    TestStorageContract storageContract;

    function setUp() public {
        storageContract = new TestStorageContract(
            StorageContract.Config(MAX_KV_SIZE, SHARD_SIZE_BITS, 2, 0, 0, 0), 0, STORAGE_COST, 0
        );
        storageContract.initialize(0, PREPAID_AMOUNT, 0, address(0x1), address(0x1));
    }

    function testMiningReward() public {
        // no key-value stored on EthStorage, only use prepaid amount as the reward
        (,, uint256 reward) = storageContract.miningRewards(0, 1);
        assertEq(reward, storageContract.paymentIn(PREPAID_AMOUNT, 0, 1));

        // 1 key-value stored on EthStorage
        storageContract.setKvEntryCount(1);
        (,, reward) = storageContract.miningRewards(0, 1);
        assertEq(reward, storageContract.paymentIn(PREPAID_AMOUNT + STORAGE_COST * 1, 0, 1));

        // 2 key-value stored on EthStorage
        storageContract.setKvEntryCount(2);
        (,, reward) = storageContract.miningRewards(0, 1);
        assertEq(reward, storageContract.paymentIn(PREPAID_AMOUNT + STORAGE_COST * 2, 0, 1));

        // 3 key-value stored on EthStorage, but the reward is capped with 4 * STORAGE_COST
        storageContract.setKvEntryCount(3);
        (,, reward) = storageContract.miningRewards(0, 1);
        assertEq(reward, storageContract.paymentIn(PREPAID_AMOUNT + STORAGE_COST * 2, 0, 1));
    }
}
