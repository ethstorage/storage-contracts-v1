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
        (,,, uint256 reward) = storageContract.miningRewards(0, 1);
        assertEq(reward, storageContract.paymentIn(PREPAID_AMOUNT, 0, 1));

        // 1 key-value stored on EthStorage
        storageContract.setKvEntryCount(1);
        (,,, reward) = storageContract.miningRewards(0, 1);
        assertEq(reward, storageContract.paymentIn(PREPAID_AMOUNT + STORAGE_COST * 1, 0, 1));

        // 2 key-value stored on EthStorage
        storageContract.setKvEntryCount(2);
        (,,, reward) = storageContract.miningRewards(0, 1);
        assertEq(reward, storageContract.paymentIn(PREPAID_AMOUNT + STORAGE_COST * 2, 0, 1));

        // 3 key-value stored on EthStorage, but the reward is capped with 4 * STORAGE_COST
        storageContract.setKvEntryCount(3);
        (,,, reward) = storageContract.miningRewards(0, 1);
        assertEq(reward, storageContract.paymentIn(PREPAID_AMOUNT + STORAGE_COST * 2, 0, 1));
    }

    function setUp1() public {
        storageContract = new TestStorageContract(
            StorageContract.Config(MAX_KV_SIZE, SHARD_SIZE_BITS, 2, 0, 0, 100), 0, STORAGE_COST, 0
        );
        storageContract.initialize(0, PREPAID_AMOUNT, 0, vm.addr(1), address(0x1));
    }

    function testWithdraw() public {
        setUp1();

        uint256 valueToSent = 3000;
        uint256 withdrawAmount = 800;

        storageContract.sendValue{value: valueToSent}();
        assertEq(storageContract.accPrepaidAmount(), valueToSent);

        storageContract.withdraw(withdrawAmount);
        assertEq(storageContract.accPrepaidAmount(), valueToSent - withdrawAmount);
        assertEq(storageContract.treasury().balance, withdrawAmount);
    }

    function testWithdrawRewardMiner() public {
        setUp1();

        uint256 valueToSent = 5000;
        uint256 withdrawAmount = 800;
        uint256 mineTs = 10000;
        uint40 kvEntryCount = 1;
        uint256 shardEntry = 1 << (SHARD_SIZE_BITS - MAX_KV_SIZE);

        storageContract.sendValue{value: valueToSent}();
        storageContract.setKvEntryCount(kvEntryCount);
        uint256 reward = storageContract.paymentIn(STORAGE_COST * kvEntryCount, 0, mineTs);
        uint256 prepaidReward = storageContract.paymentIn(PREPAID_AMOUNT, 0, mineTs);
        reward += prepaidReward;
        uint256 treasureReward = (reward * storageContract.treasuryShare()) / 10000;
        uint256 minerReward = reward - treasureReward;
        uint256 prepaidAmountCap = STORAGE_COST * (shardEntry - kvEntryCount);
        uint256 prepaidAmountSaved = storageContract.paymentIn(prepaidAmountCap, 0, mineTs) - prepaidReward;

        storageContract.rewardMiner(0, vm.addr(2), mineTs, 1);
        uint256 totalPrepaid = valueToSent + treasureReward + prepaidAmountSaved;
        assertEq(storageContract.accPrepaidAmount(), totalPrepaid);

        storageContract.withdraw(withdrawAmount);
        assertEq(storageContract.accPrepaidAmount(), totalPrepaid - withdrawAmount);
        assertEq(storageContract.treasury().balance, withdrawAmount);
        assertEq(address(storageContract).balance, valueToSent - minerReward - withdrawAmount);
    }

    function testWithdrawInsufficientFunds() public {
        uint256 valueToSent = 3000;
        uint256 withdrawAmount = 1500;

        storageContract.sendValue{value: valueToSent}();

        vm.expectRevert("StorageContract: not enough prepaid amount");
        storageContract.withdraw(withdrawAmount);
    }
}
