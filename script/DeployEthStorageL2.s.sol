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
        console.log("Start time:", startTime);
        uint256 storageCost = vm.envOr("STORAGE_COST", uint256(570000000000000000));
        uint256 dcfFactor = vm.envOr("DCF_FACTOR", uint256(340282366367469178095360967382638002176));

        uint256 minimumDiff = vm.envOr("MINIMUM_DIFF", uint256(94371840));
        uint256 prepaidAmount = vm.envOr("PREPAID_AMOUNT", uint256(119537664000000000000000));
        uint256 nonceLimit = vm.envOr("NONCE_LIMIT", uint256(1048576));
        uint256 updateLimit = vm.envOr("UPDATE_LIMIT", uint256(90));

        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        address admin = vm.envOr("OWNER_ADDRESS", deployer);

        vm.startBroadcast(deployerPrivateKey);

        bytes memory initData = abi.encodeWithSelector(
            EthStorageContractM2L2.initialize.selector,
            config,
            startTime,
            storageCost,
            dcfFactor,
            minimumDiff,
            prepaidAmount,
            nonceLimit,
            treasury,
            admin,
            updateLimit
        );

        address proxy =
            Upgrades.deployTransparentProxy("EthStorageContractM2L2.sol:EthStorageContractM2L2", admin, initData);
        console.log("Proxy address:", proxy);
        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        console.log("Proxy admin address:", proxyAdmin);

        vm.stopBroadcast();
    }
}
