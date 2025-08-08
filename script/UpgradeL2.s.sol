// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {StorageContract} from "../contracts/StorageContract.sol";
import {EthStorageContractM2L2} from "../contracts/EthStorageContractM2L2.sol";

interface IProxyAdmin {
    function upgradeAndCall(address proxy, address implementation, bytes memory data) external;
}

contract UpgradeL2 is Script {
    using Strings for uint256;

    function run() external {
        StorageContract.Config memory config = StorageContract.Config({
            maxKvSizeBits: vm.envOr("MAX_KV_SIZE_BITS", uint256(17)),
            shardSizeBits: vm.envOr("SHARD_SIZE_BITS", uint256(39)),
            randomChecks: vm.envOr("RANDOM_CHECKS", uint256(2)),
            cutoff: vm.envOr("CUTOFF", uint256(7200)),
            diffAdjDivisor: vm.envOr("DIFF_ADJ_DIVISOR", uint256(32)),
            treasuryShare: vm.envOr("TREASURY_SHARE", uint256(100))
        });
        uint256 storageCost = vm.envOr("STORAGE_COST", uint256(570000000000000000));
        uint256 dcfFactor = vm.envOr("DCF_FACTOR", uint256(340282366367469178095360967382638002176));
        uint256 updateLimit = vm.envOr("UPDATE_LIMIT", uint256(90));
        uint256 startTime = vm.envOr("START_TIME", block.timestamp);

        address proxy = vm.envAddress("PROXY");
        address admin = vm.envAddress("PROXY_ADMIN");
        console.log("Proxy address: %s", proxy);
        console.log("Admin address: %s", admin);

        vm.startBroadcast();
        EthStorageContractM2L2 impl = new EthStorageContractM2L2(config, startTime, storageCost, dcfFactor, updateLimit);
        console.log("New implementation: %s", address(impl));

        IProxyAdmin(admin).upgradeAndCall(proxy, address(impl), "");
        vm.stopBroadcast();

        console.log("Proxy upgraded to new implementation: %s", address(impl));
    }
}
