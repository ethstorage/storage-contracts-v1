// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../contracts/EthStorageContractM2L2.sol";

contract DeployEthStorageL2 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        StorageContract.Config memory config = StorageContract.Config({
            maxKvSizeBits: vm.envUint("MAX_KV_SIZE_BITS"),
            shardSizeBits: vm.envUint("SHARD_SIZE_BITS"),
            randomChecks: vm.envUint("RANDOM_CHECKS"),
            cutoff: vm.envUint("CUTOFF"),
            diffAdjDivisor: vm.envUint("DIFF_ADJ_DIVISOR"),
            treasuryShare: vm.envUint("TREASURY_SHARE")
        });

        uint256 startTime = block.timestamp;
        console.log("Start time:", startTime);
        uint256 storageCost = vm.envUint("STORAGE_COST");
        uint256 dcfFactor = vm.envUint("DCF_FACTOR");

        uint256 minimumDiff = vm.envUint("MINIMUM_DIFF");
        uint256 prepaidAmount = vm.envUint("PREPAID_AMOUNT");
        uint256 nonceLimit = vm.envUint("NONCE_LIMIT");

        uint256 updateLimit = vm.envUint("UPDATE_LIMIT");

        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address admin = vm.envAddress("OWNER_ADDRESS");
        console.log("Owner address:", admin);
        vm.startBroadcast(deployerPrivateKey);

        bytes memory initData = abi.encodeWithSelector(
            EthStorageContractM2L2.initialize.selector, minimumDiff, prepaidAmount, nonceLimit, treasury, admin
        );
        Options memory opts;
        opts.constructorData = abi.encode(config, startTime, storageCost, dcfFactor, updateLimit);

        address proxy =
            Upgrades.deployTransparentProxy("EthStorageContractM2L2.sol:EthStorageContractM2L2", admin, initData, opts);
        console.log("Proxy address:", proxy);
        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        console.log("Proxy admin address:", proxyAdmin);
        address impl = Upgrades.getImplementationAddress(proxy);
        console.log("Implementation address:", impl);

        vm.stopBroadcast();
    }
}
