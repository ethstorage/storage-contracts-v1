const fs = require("fs");
const hre = require("hardhat");
const dotenv = require("dotenv");
dotenv.config();

let ownerAddress = null;
let treasuryAddress = null;
const adminContractAddr = "";
const storageContractProxy = "";
const gasPrice = null;

const config = [
  17, // maxKvSizeBits, 131072
  30, // shardSizeBits ~ 1G
  2, // randomChecks
  7200, // cutoff = 2/3 * target internal (3 hours), 3 * 3600 * 2/3
  32, // diffAdjDivisor
  100, // treasuryShare, means 1%
];
const storageCost = 570000000000000000n; // storage cost forever per blob - https://ethresear.ch/t/ethstorage-scaling-ethereum-storage-via-l2-and-da/14223/6#incentivization-for-storing-m-physical-replicas-1
const dcfFactor = 340282366367469178095360967382638002176n; // dcfFactor, it mean 0.95 for yearly discount
const updateLimit = 90; // 45 blobs/s according to sync/encoding test, times block interval of L2

async function verifyContract(contract, args) {
  // if (!process.env.ETHERSCAN_API_KEY) {
  //   return;
  // }
  // await hre.run("verify:verify", {
  //   address: contract,
  //   constructorArguments: args,
  // });
}

async function deployContract() {
  const startTime = Math.floor(new Date().getTime() / 1000);
  console.log("Deploying contracts to network", hre.network.name);
  const [deployer] = await hre.ethers.getSigners();
  const deployerAddress = await deployer.getAddress();
  console.log("Deploying contracts with account:", deployerAddress);
  ownerAddress = deployerAddress;
  treasuryAddress = deployerAddress;

  const StorageContract = await hre.ethers.getContractFactory("EthStorageContractL2");
  // refer to https://docs.google.com/spreadsheets/d/11DHhSang1UZxIFAKYw6_Qxxb-V40Wh1lsYjY2dbIP5k/edit#gid=0
  const implContract = await StorageContract.deploy(
    config,
    startTime, // startTime
    storageCost,
    dcfFactor,
    updateLimit,
    { gasPrice: gasPrice },
  );
  await implContract.waitForDeployment();
  const impl = await implContract.getAddress();
  console.log("storage impl address is ", impl);

  const data = implContract.interface.encodeFunctionData("initialize", [
    10485760, // minimumDiff 0.1 * 1200 (20 minutes) * 1024 * 1024 / 12 = 10485760 for 0.1 replicas that can have 1M IOs in one epoch
    2334720000000000000000n, // prepaidAmount - 50% * 2^30 / 131072 * 570000000000000000, it also means 2334 QKC for half of the shard
    1048576, // nonceLimit 1024 * 1024 = 1M samples and finish sampling in 1.3s with IO rate 6144 MB/s: 4k * 2(random checks) / 6144 = 1.3s
    treasuryAddress, // treasury
    ownerAddress,
  ]);
  console.log(impl, ownerAddress, data);
  const EthStorageUpgradeableProxy = await hre.ethers.getContractFactory("EthStorageUpgradeableProxy");
  const ethStorageProxy = await EthStorageUpgradeableProxy.deploy(impl, ownerAddress, data, { gasPrice: gasPrice });
  await ethStorageProxy.waitForDeployment();
  const admin = await ethStorageProxy.admin();
  const address = await ethStorageProxy.getAddress();
  console.log("storage admin address is ", admin);
  console.log("storage contract address is ", address);
  const receipt = await hre.ethers.provider.getTransactionReceipt(ethStorageProxy.deploymentTransaction().hash);
  console.log(
    "deployed in block number",
    receipt.blockNumber,
    "on",
    new Date().toLocaleDateString([], { year: "numeric", month: "long", day: "numeric" }),
    "at",
    new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" }),
  );

  // fund 500 qkc into the storage contract to give reward for empty mining
  const ethStorage = StorageContract.attach(address);
  const tx = await ethStorage.sendValue({ value: hre.ethers.parseEther("500") });
  await tx.wait();
  const balance = hre.ethers.formatEther(await hre.ethers.provider.getBalance(address));
  console.log("balance of " + address + ": ", balance);

  // verify contract
  await verifyContract(address);
  await verifyContract(impl, [config, startTime, storageCost, dcfFactor]);

  // wait for contract finalized
  var intervalId = setInterval(async function () {
    try {
      const block = await hre.ethers.provider.getBlock("finalized");
      console.log(
        "finalized block number is",
        block.number,
        "at",
        new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" }),
      );
      if (receipt.blockNumber < block.number) {
        fs.writeFileSync(".caddr", address);
        clearInterval(intervalId);
      }
    } catch (e) {
      console.error(`EthStorage: get finalized block failed!`, e.message);
    }
  }, 60000);
}

async function updateContract() {
  const StorageContract = await hre.ethers.getContractFactory("EthStorageContractL2");

  // get start time
  const ethStorage = StorageContract.attach(storageContractProxy);
  const startTime = await ethStorage.startTime();

  // deploy
  const implContract = await StorageContract.deploy(
    config,
    startTime, // startTime
    storageCost,
    dcfFactor,
    { gasPrice: gasPrice },
  );
  await implContract.waitForDeployment();
  const impl = await implContract.getAddress();
  console.log("storage impl address is ", impl);

  // set impl
  const EthStorageAdmin = await hre.ethers.getContractAt("IProxyAdmin", adminContractAddr);
  const tx = await EthStorageAdmin.upgradeAndCall(storageContractProxy, impl, "0x");
  await tx.wait();
  console.log("update contract success!");

  // verify contract
  await verifyContract(impl, [config, startTime, storageCost, dcfFactor]);
}

async function main() {
  if (!storageContractProxy) {
    // create
    await deployContract();
  } else {
    // update
    await updateContract();
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
