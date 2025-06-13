// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {StorageContract} from "../contracts/StorageContract.sol";
import {EthStorageContractL2} from "../contracts/EthStorageContractL2.sol";
import {EthStorageUpgradeableProxy} from "../contracts/EthStorageUpgradeableProxy.sol";

contract DeployL2 is Script {
    using Strings for uint256;

    function run() external {
        // Read configuration parameters from environment variables (or use defaults)
        StorageContract.Config memory config = StorageContract.Config({
            maxKvSizeBits: vm.envOr("MAX_KV_SIZE_BITS", uint256(17)),
            shardSizeBits: vm.envOr("SHARD_SIZE_BITS", uint256(20)),
            randomChecks: vm.envOr("RANDOM_CHECKS", uint256(2)),
            cutoff: vm.envOr("CUTOFF", uint256(7200)),
            diffAdjDivisor: vm.envOr("DIFF_ADJ_DIVISOR", uint256(32)),
            treasuryShare: vm.envOr("TREASURY_SHARE", uint256(100))
        });

        uint256 storageCost = vm.envOr("STORAGE_COST", uint256(570000000000000000)); // 0.57 ETH in wei
        uint256 dcfFactor = vm.envOr("DCF_FACTOR", uint256(340282366367469178095360967382638002176));
        uint256 updateLimit = vm.envOr("UPDATE_LIMIT", uint256(90));
        uint256 startTime = block.timestamp;

        // Get deployer address
        address deployer = msg.sender;
        console.log("Deployer address: %s", deployer);

        vm.startBroadcast();

        // Deploy the implementation contract
        EthStorageContractL2 impl = new EthStorageContractL2(config, startTime, storageCost, dcfFactor, updateLimit);

        // Prepare initialization data
        bytes memory data = abi.encodeWithSelector(
            impl.initialize.selector,
            vm.envOr("MINIMUM_DIFF", uint256(943718)), // minimumDiff
            vm.envOr("PREPAID_AMOUNT", uint256(1195376640000000000000000)), // prepaidAmount
            vm.envOr("NONCE_LIMIT", uint256(1048576)), // nonceLimit
            deployer, // treasuryAddress
            deployer // ownerAddress
        );

        // Deploy the proxy contract
        EthStorageUpgradeableProxy proxy = new EthStorageUpgradeableProxy(address(impl), deployer, data);

        // Fund the proxy contract
        payable(address(proxy)).transfer(0.001 ether);

        vm.stopBroadcast();

        console.log("Start time: %s", startTime.toString());
        console.log("Block number: %s", block.number.toString());
        console.log("Implementation address: %s", address(impl));
        console.log("Proxy address: %s", address(proxy));
        console.log("Proxy contract balance: %s", address(proxy).balance.toString());
    }
}
