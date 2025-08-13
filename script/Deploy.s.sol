// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "openzeppelin-foundry-upgrades/Upgrades.sol";

import "../contracts/EthStorageContractM1.sol";
import "../contracts/EthStorageContractM1L2.sol";
import "../contracts/EthStorageContractM2.sol";
import "../contracts/EthStorageContractM2L2.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        string memory contractName = vm.envString("CONTRACT_NAME");
        console.log("Contract name:", contractName);

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

        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        console.log("Treasury address:", treasury);
        address owner = vm.envOr("OWNER_ADDRESS", deployer);
        console.log("Owner address:", owner);

        vm.startBroadcast(deployerPrivateKey);

        string memory contractFQN;
        bytes memory initData;
        Options memory opts;

        bytes32 nameHash = keccak256(bytes(contractName));

        if (nameHash == keccak256("EthStorageContractM1")) {
            contractFQN = "EthStorageContractM1.sol:EthStorageContractM1";
            initData = abi.encodeWithSelector(
                EthStorageContractM1.initialize.selector,
                minimumDiff,
                prepaidAmount,
                nonceLimit,
                treasury,
                owner
            );
            opts.constructorData = abi.encode(config, startTime, storageCost, dcfFactor);

        } else if (nameHash == keccak256("EthStorageContractM1L2")) {
            uint256 updateLimit = vm.envUint("UPDATE_LIMIT");
            contractFQN = "EthStorageContractM1L2.sol:EthStorageContractM1L2";
            initData = abi.encodeWithSelector(
                EthStorageContractM1L2.initialize.selector,
                minimumDiff,
                prepaidAmount,
                nonceLimit,
                treasury,
                owner
            );
            opts.constructorData = abi.encode(config, startTime, storageCost, dcfFactor, updateLimit);

        } else if (nameHash == keccak256("EthStorageContractM2")) {
            contractFQN = "EthStorageContractM2.sol:EthStorageContractM2";
            initData = abi.encodeWithSelector(
                EthStorageContractM2.initialize.selector,
                minimumDiff,
                prepaidAmount,
                nonceLimit,
                treasury,
                owner
            );
            opts.constructorData = abi.encode(config, startTime, storageCost, dcfFactor);

        } else if (nameHash == keccak256("EthStorageContractM2L2")) {
            uint256 updateLimit = vm.envUint("UPDATE_LIMIT");
            contractFQN = "EthStorageContractM2L2.sol:EthStorageContractM2L2";
            initData = abi.encodeWithSelector(
                EthStorageContractM2L2.initialize.selector,
                minimumDiff,
                prepaidAmount,
                nonceLimit,
                treasury,
                owner
            );
            opts.constructorData = abi.encode(config, startTime, storageCost, dcfFactor, updateLimit);

        } else {
            revert(string(abi.encodePacked("Unsupported CONTRACT_NAME: ", contractName)));
        }

        address proxy = Upgrades.deployTransparentProxy(contractFQN, owner, initData, opts);
        
        console.log("Proxy address:", proxy);
        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        console.log("Proxy admin address:", proxyAdmin);
        address impl = Upgrades.getImplementationAddress(proxy);
        console.log("Implementation address:", impl);

        vm.stopBroadcast();
    }
}
