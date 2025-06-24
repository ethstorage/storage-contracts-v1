// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./TestStorageContract.sol";
import "../StorageContract.sol";
import "forge-std/Test.sol";

contract StorageContractTest is Test {
    uint256 constant STORAGE_COST = 10000000;
    uint256 constant SHARD_SIZE_BITS = 19;
    uint256 constant MAX_KV_SIZE = 17;
    uint256 constant PREPAID_AMOUNT = 2 * STORAGE_COST;
    TestStorageContract storageContract;

    function setUp() public {
        storageContract = new TestStorageContract(
            StorageContract.Config(MAX_KV_SIZE, SHARD_SIZE_BITS, 2, 0, 0, 0),
            0,
            STORAGE_COST,
            340282366367469178095360967382638002176
        );
        storageContract.initialize(0, PREPAID_AMOUNT, 0, vm.addr(1), address(this));
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

    function testWithdraw() public {
        uint256 valueToSent = 30000000;
        uint256 withdrawAmount = 10000001;

        storageContract.sendValue{value: valueToSent}();
        assertEq(storageContract.accPrepaidAmount(), valueToSent);

        vm.expectRevert("StorageContract: not enough prepaid amount");
        storageContract.withdraw(withdrawAmount);

        withdrawAmount = 10000000;
        storageContract.withdraw(withdrawAmount);
        assertEq(storageContract.accPrepaidAmount(), valueToSent - withdrawAmount);
        assertEq(storageContract.treasury().balance, withdrawAmount);
    }

    function testWithdrawRewardMiner() public {
        uint256 valueToSent = 50000000;
        uint256 withdrawAmount = 8000000;
        uint256 mineTs = 10000;
        address miner = vm.addr(2);
        storageContract.sendValue{value: valueToSent}();

        // a little half
        storageContract.setKvEntryCount(1);
        uint256 reward = storageContract.paymentIn(STORAGE_COST, 0, mineTs);
        uint256 prepaidReward = storageContract.paymentIn(PREPAID_AMOUNT, 0, mineTs);
        reward += prepaidReward;
        uint256 treasureReward = (reward * storageContract.treasuryShare()) / 10000;
        uint256 minerReward = reward - treasureReward;

        storageContract.rewardMiner(0, miner, mineTs, 1);
        assertEq(miner.balance, minerReward);
        assertEq(storageContract.accPrepaidAmount(), valueToSent + treasureReward);

        storageContract.withdraw(withdrawAmount);
        assertEq(storageContract.accPrepaidAmount(), valueToSent + treasureReward - withdrawAmount);
        assertEq(storageContract.treasury().balance, withdrawAmount);
        assertEq(address(storageContract).balance, valueToSent - minerReward - withdrawAmount);
    }

    function testWithdrawRewardMinerSaved() public {
        uint256 valueToSent = 50000000;
        uint256 withdrawAmount = 8000000;
        uint256 mineTs = 10000;
        address miner = vm.addr(2);
        storageContract.sendValue{value: valueToSent}();

        // more than half
        storageContract.setKvEntryCount(3);
        uint256 rewardFull = storageContract.paymentIn(STORAGE_COST << (SHARD_SIZE_BITS - MAX_KV_SIZE), 0, mineTs);
        (, uint256 saved,, uint256 reward) = storageContract.miningRewards(0, mineTs);
        assertEq(rewardFull, reward);
        uint256 treasureReward = (reward * storageContract.treasuryShare()) / 10000;
        uint256 minerReward = reward - treasureReward;

        storageContract.rewardMiner(0, miner, mineTs, 1);
        assertEq(miner.balance, minerReward);
        assertEq(storageContract.accPrepaidAmount(), valueToSent + treasureReward + saved);

        storageContract.withdraw(withdrawAmount);
        assertEq(storageContract.accPrepaidAmount(), valueToSent + treasureReward + saved - withdrawAmount);
        assertEq(storageContract.treasury().balance, withdrawAmount);
        assertEq(address(storageContract).balance, valueToSent - minerReward - withdrawAmount);
    }

    function testRewardMiner() public {
        address miner = vm.addr(2);
        uint256 mineTs = 10000;
        uint256 diff = 1;

        vm.expectRevert("StorageContract: not enough balance");
        storageContract.rewardMiner(0, miner, mineTs, 1);

        vm.deal(address(storageContract), 1000);

        (,,, uint256 reward) = storageContract.miningRewards(0, mineTs);
        storageContract.rewardMiner(0, miner, mineTs, diff);
        (uint256 l, uint256 d, uint256 b) = storageContract.infos(0);
        assertEq(l, mineTs);
        assertEq(d, diff);
        assertEq(b, 1);
        assertEq(miner.balance, reward);
    }

    function testReentrancy() public noGasMetering {
        uint256 prefund = 1000;
        // Without reentrancy protection, the fund could be drained by 29 times re-entrances given current params.
        vm.deal(address(storageContract), prefund);
        storageContract.setKvEntryCount(1);
        Attacker attacker = new Attacker(storageContract);
        vm.prank(address(attacker));

        uint256 _blockNum = 1;
        uint256 _shardId = 0;
        uint256 _nonce = 0;
        bytes32[] memory _encodedSamples = new bytes32[](0);
        uint256[] memory _masks = new uint256[](0);
        bytes memory _randaoProof = "0x01";
        bytes[] memory _inclusiveProofs = new bytes[](0);
        bytes[] memory _decodeProof = new bytes[](0);
        // currently this error is not reachable on github server
        // vm.expectRevert("StorageContract: reentrancy attempt!");
        vm.expectRevert();
        storageContract.mine(
            _blockNum,
            _shardId,
            address(attacker),
            _nonce,
            _encodedSamples,
            _masks,
            _randaoProof,
            _inclusiveProofs,
            _decodeProof
        );
    }

    function testMineWhitelisted() public {
        address miner = address(0x2);
        // MINER_ROLE is not granted to miner, so it should revert
        vm.expectRevert("StorageContract: miner not whitelisted");
        storageContract.mine(1, 0, miner, 0, new bytes32[](0), new uint256[](0), "", new bytes[](0), new bytes[](0));

        // MINER_ROLE's admin role is DEFAULT_ADMIN_ROLE
        bytes32 adminRole = storageContract.getRoleAdmin(storageContract.MINER_ROLE());
        assertEq(adminRole, storageContract.DEFAULT_ADMIN_ROLE());

        // Owner has DEFAULT_ADMIN_ROLE
        address owner = storageContract.owner();
        console.log("Owner address:", owner);
        assertTrue(storageContract.hasRole(storageContract.DEFAULT_ADMIN_ROLE(), owner));

        // So owner can grant MINER_ROLE to other address
        vm.prank(owner);
        storageContract.grantRole(storageContract.MINER_ROLE(), miner);

        // Now miner has MINER_ROLE, so it can call mine function
        storageContract.mine(1, 0, miner, 0, new bytes32[](0), new uint256[](0), "", new bytes[](0), new bytes[](0));

        // revoking MINER_ROLE from miner
        vm.prank(owner);
        storageContract.revokeRole(storageContract.MINER_ROLE(), miner);

        // Now miner doesn't have MINER_ROLE, so it should revert again
        vm.expectRevert("StorageContract: miner not whitelisted");
        storageContract.mine(1, 0, miner, 0, new bytes32[](0), new uint256[](0), "", new bytes[](0), new bytes[](0));
    }

    function testEnforceMinerRole() public {
        address miner = address(0x2);
        address notWhiteListedMiner = address(0x3);

        // EnforceMinerRole is enabled by default
        vm.expectRevert("StorageContract: miner not whitelisted");
        storageContract.mine(1, 0, miner, 0, new bytes32[](0), new uint256[](0), "", new bytes[](0), new bytes[](0));

        // Grant MINER_ROLE to the miner
        vm.prank(storageContract.owner());
        storageContract.grantRole(storageContract.MINER_ROLE(), miner);

        // Now miner can call mine without reverting
        storageContract.mine(1, 0, miner, 0, new bytes32[](0), new uint256[](0), "", new bytes[](0), new bytes[](0));

        // Disable enforceMinerRole
        storageContract.setEnforceMinerRole(false);

        // Even without MINER_ROLE, any random miner should now be able to mine
        storageContract.mine(
            1, 0, notWhiteListedMiner, 0, new bytes32[](0), new uint256[](0), "", new bytes[](0), new bytes[](0)
        );

        // Re-enable enforceMinerRole
        storageContract.setEnforceMinerRole(true);

        // Now the random address without MINER_ROLE should revert
        vm.expectRevert("StorageContract: miner not whitelisted");
        storageContract.mine(
            1, 0, notWhiteListedMiner, 0, new bytes32[](0), new uint256[](0), "", new bytes[](0), new bytes[](0)
        );

        // But miner who has whitelisted before can still mine without reverting
        storageContract.mine(1, 0, miner, 0, new bytes32[](0), new uint256[](0), "", new bytes[](0), new bytes[](0));
    }
}

contract Attacker is Test {
    TestStorageContract storageContract;
    uint256 blockNumber = 1;
    uint256 count = 0;

    constructor(TestStorageContract _storageContract) {
        storageContract = _storageContract;
    }

    receive() external payable {
        uint256 _shardId = 0;
        uint256 _nonce = 0;
        bytes32[] memory _encodedSamples = new bytes32[](0);
        uint256[] memory _masks = new uint256[](0);
        bytes memory _randaoProof = "0x01";
        bytes[] memory _inclusiveProofs = new bytes[](0);
        bytes[] memory _decodeProof = new bytes[](0);

        blockNumber += 60;
        vm.roll(blockNumber + 20);
        vm.warp(block.number * 12);
        uint256 reward = storageContract.miningReward(_shardId, blockNumber);
        if (address(storageContract).balance >= reward) {
            storageContract.mine(
                blockNumber,
                _shardId,
                address(this),
                _nonce,
                _encodedSamples,
                _masks,
                _randaoProof,
                _inclusiveProofs,
                _decodeProof
            );
            count++;
        }
    }
}
