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
    uint256 private deployerPrivateKey;
    address private deployer;
    string private contractName;

    function setUp() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        contractName = vm.envString("CONTRACT_NAME");
        console.log("Contract name:", contractName);

        _validateContractName(contractName);
        _validateEnvironmentVariables(contractName);
    }

    function run() external {
        address owner = vm.envOr("OWNER_ADDRESS", deployer);
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
        address proxyAddress = vm.envAddress("PROXY");
        console.log("Proxy address:", proxyAddress);
        uint256 startTime = vm.envUint("START_TIME");

        string memory contractFQN;
        bytes memory constructorData;
        (contractFQN, constructorData,) = _getDeploymentData(contractName, deployer, startTime);
        Options memory opts;
        opts.constructorData = constructorData;

        opts.referenceBuildInfoDir = vm.envString("REFERENCE_BUILD_INFO_DIR");
        opts.referenceContract = vm.envString("REFERENCE_CONTRACT");
        vm.startBroadcast(deployerPrivateKey);
        Upgrades.upgradeProxy(proxyAddress, contractFQN, "", opts);

        console.log("Upgrade completed successfully!");
        address newImpl = Upgrades.getImplementationAddress(proxyAddress);
        console.log("New implementation address:", newImpl);

        vm.stopBroadcast();
    }

    function _validateContractName(string memory _contractName) internal pure {
        bytes32 nameHash = keccak256(bytes(_contractName));

        require(
            nameHash == keccak256("EthStorageContractM1") || nameHash == keccak256("EthStorageContractM1L2")
                || nameHash == keccak256("EthStorageContractM2") || nameHash == keccak256("EthStorageContractM2L2"),
            string(abi.encodePacked("Unsupported CONTRACT_NAME: ", _contractName))
        );
    }

    function _validateEnvironmentVariables(string memory _contractName) internal view {
        // Check required basic variables
        vm.envUint("MAX_KV_SIZE_BITS");
        vm.envUint("SHARD_SIZE_BITS");
        vm.envUint("RANDOM_CHECKS");
        vm.envUint("CUTOFF");
        vm.envUint("DIFF_ADJ_DIVISOR");
        vm.envUint("TREASURY_SHARE");
        vm.envUint("STORAGE_COST");
        vm.envUint("DCF_FACTOR");
        vm.envUint("MINIMUM_DIFF");
        vm.envUint("PREPAID_AMOUNT");
        vm.envUint("NONCE_LIMIT");

        bytes32 nameHash = keccak256(bytes(_contractName));
        if (nameHash == keccak256("EthStorageContractM1L2") || nameHash == keccak256("EthStorageContractM2L2")) {
            vm.envUint("UPDATE_LIMIT");
        }
    }

    function _getDeploymentData(string memory _contractName, address _deployer, uint256 startTime)
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

        address treasury = vm.envOr("TREASURY_ADDRESS", _deployer);
        console.log("Treasury address:", treasury);
        address owner = vm.envOr("OWNER_ADDRESS", _deployer);
        console.log("Owner address:", owner);

        bytes32 nameHash = keccak256(bytes(_contractName));

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
        }
        return (contractFQN, constructorData, initData);
    }
}
