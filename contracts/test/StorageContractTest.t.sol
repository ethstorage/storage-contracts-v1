// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./TestStorageContract.sol";
import "../StorageContract.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

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
        storageContract.initialize(0, PREPAID_AMOUNT, 0, vm.addr(1), address(0x1));
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

    function testRewardMiner() public {
        address miner = vm.addr(2);
        uint256 mineTs = 10000;
        uint256 diff = 1;

        vm.expectRevert("StorageContract: not enough balance");
        storageContract.rewardMiner(0, miner, mineTs, 1);

        vm.deal(address(storageContract), 1000);

        (,, uint256 reward) = storageContract.miningRewards(0, mineTs);
        storageContract.rewardMiner(0, miner, mineTs, diff);
        (uint256 l, uint256 d, uint256 b) = storageContract.infos(0);
        assertEq(l, mineTs);
        assertEq(d, diff);
        assertEq(b, 1);
        assertEq(miner.balance, reward);
    }

    function testReentrancy() public {
        vm.pauseGasMetering();
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

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
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
}

contract Attacker {
    // cannot access imported vm directly
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm vm = Vm(VM_ADDRESS);
    TestStorageContract storageContract;
    uint256 blockNumber = 1;
    uint256 count = 0;

    constructor(TestStorageContract _storageContract) {
        storageContract = _storageContract;
    }

    fallback() external payable {
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
