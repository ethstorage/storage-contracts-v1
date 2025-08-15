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
    function setUp() public {}

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        string memory contractName = vm.envString("CONTRACT_NAME");
        console.log("Contract name:", contractName);
        address owner = vm.envOr("OWNER_ADDRESS", deployer);
        console.log("Owner address:", owner);
        uint256 startTime = block.timestamp;

        string memory contractFQN;
        bytes memory constructorData;
        bytes memory initData;
        
        (contractFQN, constructorData, initData) = _getDeploymentData(contractName, deployer, startTime);
        Options memory opts;
        opts.constructorData = constructorData;

        vm.startBroadcast(deployerPrivateKey);
        address proxy = Upgrades.deployTransparentProxy(contractFQN, owner, initData, opts);
        vm.stopBroadcast();

        console.log("Proxy address:", proxy);
        address proxyAdmin = Upgrades.getAdminAddress(proxy);
        console.log("Proxy admin address:", proxyAdmin);
        address impl = Upgrades.getImplementationAddress(proxy);
        console.log("Implementation address:", impl);
    }

    function upgrade() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);
        string memory contractName = vm.envString("CONTRACT_NAME");
        console.log("Contract name:", contractName);
        address proxyAddress = vm.envAddress("PROXY");
        console.log("Proxy address:", proxyAddress);
        uint256 startTime = vm.envUint("START_TIME");
        
        // Declare variables at function scope
        string memory contractFQN;
        bytes memory constructorData;
        
        (contractFQN, constructorData, ) = _getDeploymentData(contractName, deployer, startTime);
        Options memory opts;
        opts.constructorData = constructorData;

        // Use the same directory and name for the new version. Refer to
        // https://docs.openzeppelin.com/upgrades-plugins/foundry-upgrades#upgrade_a_proxy_or_beacon

        try vm.envString("REFERENCE_BUILD_INFO_DIR") returns (string memory referenceBuildInfoDir) {
            if (bytes(referenceBuildInfoDir).length > 0) {
                opts.referenceBuildInfoDir = referenceBuildInfoDir;
                console.log("Using reference build info dir:", referenceBuildInfoDir);
            }
        } catch {
            console.log("WARNING: REFERENCE_BUILD_INFO_DIR not set");
        }

        try vm.envString("REFERENCE_CONTRACT") returns (string memory referenceContract) {
            if (bytes(referenceContract).length > 0) {
                opts.referenceContract = referenceContract;
                console.log("Using reference contract:", referenceContract);
            }
        } catch {
            console.log("WARNING: REFERENCE_CONTRACT not set");
        }
        
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        Upgrades.upgradeProxy(proxyAddress, contractFQN, "", opts);

        console.log("Upgrade completed successfully!");
        address newImpl = Upgrades.getImplementationAddress(proxyAddress);
        console.log("New implementation address:", newImpl);

        vm.stopBroadcast();
    }

    function _getDeploymentData(string memory contractName, address deployer, uint256 startTime)
        internal
        view
        returns (string memory contractFQN, bytes memory constructorData, bytes memory initData)
    {
        StorageContract.Config memory config = StorageContract.Config({
            maxKvSizeBits: vm.envUint("MAX_KV_SIZE_BITS"),
            shardSizeBits: vm.envUint("SHARD_SIZE_BITS"),
            randomChecks: vm.envUint("RANDOM_CHECKS"),
            cutoff: vm.envUint("CUTOFF"),
            diffAdjDivisor: vm.envUint("DIFF_ADJ_DIVISOR"),
            treasuryShare: vm.envUint("TREASURY_SHARE")
        });

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

        bytes32 nameHash = keccak256(bytes(contractName));

        if (nameHash == keccak256("EthStorageContractM1")) {
            contractFQN = "EthStorageContractM1.sol:EthStorageContractM1";
            initData = abi.encodeWithSelector(
                EthStorageContractM1.initialize.selector, minimumDiff, prepaidAmount, nonceLimit, treasury, owner
            );
            constructorData = abi.encode(config, startTime, storageCost, dcfFactor);
        } else if (nameHash == keccak256("EthStorageContractM1L2")) {
            uint256 updateLimit = vm.envUint("UPDATE_LIMIT");
            contractFQN = "EthStorageContractM1L2.sol:EthStorageContractM1L2";
            initData = abi.encodeWithSelector(
                EthStorageContractM1L2.initialize.selector, minimumDiff, prepaidAmount, nonceLimit, treasury, owner
            );
            constructorData = abi.encode(config, startTime, storageCost, dcfFactor, updateLimit);
        } else if (nameHash == keccak256("EthStorageContractM2")) {
            contractFQN = "EthStorageContractM2.sol:EthStorageContractM2";
            initData = abi.encodeWithSelector(
                EthStorageContractM2.initialize.selector, minimumDiff, prepaidAmount, nonceLimit, treasury, owner
            );
            constructorData = abi.encode(config, startTime, storageCost, dcfFactor);
        } else if (nameHash == keccak256("EthStorageContractM2L2")) {
            uint256 updateLimit = vm.envUint("UPDATE_LIMIT");
            contractFQN = "EthStorageContractM2L2.sol:EthStorageContractM2L2";
            initData = abi.encodeWithSelector(
                EthStorageContractM2L2.initialize.selector, minimumDiff, prepaidAmount, nonceLimit, treasury, owner
            );
            constructorData = abi.encode(config, startTime, storageCost, dcfFactor, updateLimit);
        } else {
            revert(string(abi.encodePacked("Unsupported CONTRACT_NAME: ", contractName)));
        }
        return (contractFQN, constructorData, initData);
    }
}
