const hre = require("hardhat");
const dotenv = require("dotenv")
dotenv.config()


let ownerAddress = null;
let treasuryAddress = null;
const adminContractAddr = "";
const storageContractProxy = "";
const gasPrice = null;

const config = [
  17, // maxKvSizeBits, 131072
  39, // shardSizeBits ~ 512G
  2, // randomChecks
  7200, // cutoff = 2/3 * target internal (3 hours), 3 * 3600 * 2/3
  32, // diffAdjDivisor
  100, // treasuryShare, means 1%
];
const storageCost = 1500000000000000; // storageCost - 1,500,000Gwei forever per blob - https://ethresear.ch/t/ethstorage-scaling-ethereum-storage-via-l2-and-da/14223/6#incentivization-for-storing-m-physical-replicas-1
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

  const [deployer] = await hre.ethers.getSigners();
  ownerAddress = deployer.address;
  treasuryAddress = deployer.address;

  const StorageContract = await hre.ethers.getContractFactory("EthStorageContractL2");
  // refer to https://docs.google.com/spreadsheets/d/11DHhSang1UZxIFAKYw6_Qxxb-V40Wh1lsYjY2dbIP5k/edit#gid=0
  const implContract = await StorageContract.deploy(
    config,
    startTime, // startTime
    storageCost,
    dcfFactor,
    updateLimit,
    { gasPrice: gasPrice }
  );
  await implContract.deployed();
  const impl = implContract.address;
  console.log("storage impl address is ", impl);

  const data = implContract.interface.encodeFunctionData("initialize", [
    94371840, // minimumDiff 0.1 * 3 * 3600 * 1024 * 1024 / 12 = 94371840 for 0.1 replicas that can have 1M IOs in one epoch
    3145728000000000000000n, // prepaidAmount - 50% * 2^39 / 131072 * 1500000Gwei, it also means 3145 ETH for half of the shard
    1048576, // nonceLimit 1024 * 1024 = 1M samples and finish sampling in 1.3s with IO rate 6144 MB/s: 4k * 2(random checks) / 6144 = 1.3s
    treasuryAddress, // treasury
    ownerAddress,
  ]);
  console.log(impl, ownerAddress, data);
  const EthStorageUpgradeableProxy = await hre.ethers.getContractFactory("EthStorageUpgradeableProxy");
  const ethStorageProxy = await EthStorageUpgradeableProxy.deploy(impl, ownerAddress, data, { gasPrice: gasPrice });
  await ethStorageProxy.deployed();
  const admin = await ethStorageProxy.admin();

  console.log("storage admin address is ", admin);
  console.log("storage contract address is ", ethStorageProxy.address);
  const receipt = await hre.ethers.provider.getTransactionReceipt(ethStorageProxy.deployTransaction.hash);
  console.log(
    "deployed in block number",
    receipt.blockNumber,
    "at",
    new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })
  );

  // fund 50 qkc into the storage contract to give reward for empty mining
  const ethStorage = StorageContract.attach(ethStorageProxy.address);
  const tx = await ethStorage.sendValue({ value: hre.ethers.utils.parseEther("50") });
  await tx.wait();
  console.log("balance of " + ethStorage.address, await hre.ethers.provider.getBalance(ethStorage.address));

  // verify contract
  await verifyContract(ethStorageProxy.address);
  await verifyContract(impl, [config, startTime, storageCost, dcfFactor]);
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
    { gasPrice: gasPrice }
  );
  await implContract.deployed();
  const impl = implContract.address;
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
