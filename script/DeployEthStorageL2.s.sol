// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../contracts/EthStorageContractL2.sol";

contract DeployEthStorageL2Script is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deploying from address:", deployer);

        StorageContract.Config memory config = StorageContract.Config({
            maxKvSizeBits: vm.envOr("MAX_KV_SIZE_BITS", uint256(17)),
            shardSizeBits: vm.envOr("SHARD_SIZE_BITS", uint256(39)),
            randomChecks: vm.envOr("RANDOM_CHECKS", uint256(2)),
            cutoff: vm.envOr("CUTOFF", uint256(7200)),
            diffAdjDivisor: vm.envOr("DIFF_ADJ_DIVISOR", uint256(32)),
            treasuryShare: vm.envOr("TREASURY_SHARE", uint256(100))
        });
        
        uint256 startTime = block.timestamp;
        uint256 storageCost = vm.envOr("STORAGE_COST", uint256(570000000000000000));
        uint256 dcfFactor = vm.envOr("DCF_FACTOR", uint256(340282366367469178095360967382638002176));
        uint256 updateLimit = vm.envOr("UPDATE_LIMIT", uint256(90));
        
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);

        vm.startBroadcast(deployerPrivateKey);

        EthStorageContractL2 implementation = new EthStorageContractL2(
            config,
            startTime,
            storageCost,
            dcfFactor,
            updateLimit
        );
        console.log("Implementation address:", address(implementation));

        bytes memory initData = abi.encodeWithSelector(
            EthStorageContractL2.initialize.selector,
            deployer,  
            treasury  
        );

        address proxy = Upgrades.deployTransparentProxy(
            address(implementation),
            deployer, 
            initData
        );
        
        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        vm.stopBroadcast();

        console.log("Start time:", startTime);
        console.log("Implementation address:", address(implementation));
        console.log("Proxy address:", proxy);
        console.log("Proxy admin address:", proxyAdmin);
        console.log("Treasury address:", treasury);
        console.log("Update limit:", updateLimit);
        
        console.log("Config - maxKvSizeBits:", config.maxKvSizeBits);
        console.log("Config - shardSizeBits:", config.shardSizeBits);
        console.log("Config - randomChecks:", config.randomChecks);
        console.log("Config - cutoff:", config.cutoff);
        console.log("Config - diffAdjDivisor:", config.diffAdjDivisor);
        console.log("Config - treasuryShare:", config.treasuryShare);
        console.log("Storage cost:", storageCost);
        console.log("DCF factor:", dcfFactor);
    }
}