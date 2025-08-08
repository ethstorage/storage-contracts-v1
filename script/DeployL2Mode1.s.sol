// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {StorageContract} from "../contracts/StorageContract.sol";
import {EthStorageContractM1L2} from "../contracts/EthStorageContractM1L2.sol";
import {EthStorageUpgradeableProxy} from "../contracts/EthStorageUpgradeableProxy.sol";

contract DeployL2 is Script {
    using Strings for uint256;

    function run() external {
        uint256 prefund = vm.envOr("INITIAL_BALANCE", uint256(5000)); // default to 5000 QKC
        address deployer = msg.sender;
        console.log("Deployer address: %s", deployer);
        // Ensure the deployer has enough balance
        require(deployer.balance >= prefund + 1 ether, "Deployer does not have enough balance");
        // Read configuration parameters from environment variables (or use defaults)
        StorageContract.Config memory config = StorageContract.Config({
            maxKvSizeBits: vm.envOr("MAX_KV_SIZE_BITS", uint256(17)), // 131072
            shardSizeBits: vm.envOr("SHARD_SIZE_BITS", uint256(39)), // ~ 512G
            randomChecks: vm.envOr("RANDOM_CHECKS", uint256(2)),
            cutoff: vm.envOr("CUTOFF", uint256(7200)), // cutoff = 2/3 * target internal (3 hours), 3 * 3600 * 2/3
            diffAdjDivisor: vm.envOr("DIFF_ADJ_DIVISOR", uint256(32)),
            treasuryShare: vm.envOr("TREASURY_SHARE", uint256(100)) // 1%
        });
        uint256 storageCost = vm.envOr("STORAGE_COST", uint256(570000000000000000)); // storage cost per blob - https://ethresear.ch/t/ethstorage-scaling-ethereum-storage-via-l2-and-da/14223/6#incentivization-for-storing-m-physical-replicas-1
        uint256 dcfFactor = vm.envOr("DCF_FACTOR", uint256(340282366367469178095360967382638002176)); // 0.95 for yearly discount
        uint256 updateLimit = vm.envOr("UPDATE_LIMIT", uint256(90)); // 45 blobs/s according to sync/encoding test, times block interval of L2

        uint256 startTime = block.timestamp;

        // print configuration parameters
        console.log("Configuration parameters:");
        console.log("\tmaxKvSizeBits: %s", config.maxKvSizeBits.toString());
        console.log("\tshardSizeBits: %s", config.shardSizeBits.toString());
        console.log("\trandomChecks: %s", config.randomChecks.toString());
        console.log("\tcutoff: %s", config.cutoff.toString());
        console.log("\tdiffAdjDivisor: %s", config.diffAdjDivisor.toString());
        console.log("\ttreasuryShare: %s", config.treasuryShare.toString());
        console.log("\tstorageCost: %s", storageCost.toString());
        console.log("\tdcfFactor: %s", dcfFactor.toString());
        console.log("\tupdateLimit: %s", updateLimit.toString());
        console.log("\tstartTime: %s", startTime.toString());

        uint256 minimumDiff = vm.envOr("MINIMUM_DIFF", uint256(94371840)); // minimumDiff 0.1 * 3 * 3600 * 1024 * 1024 / 12 = 94371840 for 0.1 replicas that can have 1M IOs in one epoch
        uint256 prepaidAmount = vm.envOr("PREPAID_AMOUNT", uint256(1195376640000000000000000)); // prepaidAmount - 50% * 2^39 / 131072 * 570000000000000000, it also means around 1,200,000 QKC for half of the shard
        uint256 nonceLimit = vm.envOr("NONCE_LIMIT", uint256(1048576)); // nonceLimit 1024 * 1024 = 1M samples and finish sampling in 1.3s with IO rate 6144 MB/s: 4k * 2(random checks) / 6144 = 1.3s

        console.log("\tminimumDiff: %s", minimumDiff.toString());
        console.log("\tprepaidAmount: %s", prepaidAmount.toString());
        console.log("\tnonceLimit: %s", nonceLimit.toString());

        vm.startBroadcast();

        // Deploy the implementation contract
        EthStorageContractM1L2 impl =
            new EthStorageContractM1L2(config, startTime, storageCost, dcfFactor, updateLimit);

        // Prepare initialization data
        bytes memory data = abi.encodeWithSelector(
            impl.initialize.selector,
            minimumDiff,
            prepaidAmount,
            nonceLimit,
            deployer, // treasuryAddress
            deployer // ownerAddress
        );

        // Deploy the proxy contract
        EthStorageUpgradeableProxy proxy = new EthStorageUpgradeableProxy(address(impl), deployer, data);

        // Fund the proxy contract
        payable(address(proxy)).transfer(prefund * 1 ether);
        vm.stopBroadcast();

        console.log("Start time: %s", startTime.toString());
        console.log("Block number: %s", block.number.toString());
        console.log("Implementation address: %s", address(impl));
        console.log("Admin address: %s", proxy.admin());
        console.log("Proxy address: %s", address(proxy));
        console.log("Proxy contract balance: %s", address(proxy).balance.toString());
    }
}
