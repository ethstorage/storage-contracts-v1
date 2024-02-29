const hre = require("hardhat");

let ownerAddress = null;
let treasuryAddress = null;
const adminContractAddr = "0x11aceF404143514dbe0C1477250605646754F9e6";
const storageContractProxy = "0x804C520d3c084C805E37A35E90057Ac32831F96f";
const gasPrice = null;

const startTime = Math.floor(new Date().getTime() / 1000);
const params = [
  1500000000000000, // storageCost - 1,500,000Gwei forever per blob - https://ethresear.ch/t/ethstorage-scaling-ethereum-storage-via-l2-and-da/14223/6#incentivization-for-storing-m-physical-replicas-1
  340282366367469178095360967382638002176n, // dcfFactor, it mean 0.95 for yearly discount
  startTime, // startTime

  17, // maxKvSizeBits, 131072
  39, // shardSizeBits ~ 512G
  2, // randomChecks
  7200, // cutoff = 2/3 * target internal (3 hours), 3 * 3600 * 2/3
  32, // diffAdjDivisor
  100, // treasuryShare, means 1%
];

async function deployCloneImpl() {
  const StorageCloneFactory = await hre.ethers.getContractFactory("EthStorageCloneFactory");
  const cloneFactory = await StorageCloneFactory.deploy();
  await cloneFactory.deployed();
  console.log("storage clone factory address is ", cloneFactory.address);

  // create impl
  let tx = await cloneFactory.createCloneImpl(params, {gasPrice: gasPrice});
  tx = await tx.wait();
  const log = cloneFactory.interface.parseLog(tx.logs[0]);
  const impl = log.args[0];
  console.log("storage impl address is ", impl);
  return impl;
}

async function deployContract() {
  const [deployer] = await hre.ethers.getSigners();
  ownerAddress = deployer.address;
  treasuryAddress = deployer.address;

  const impl = await deployCloneImpl();
  const StorageContract = await hre.ethers.getContractFactory("TestEthStorageContractKZG");
  // refer to https://docs.google.com/spreadsheets/d/11DHhSang1UZxIFAKYw6_Qxxb-V40Wh1lsYjY2dbIP5k/edit#gid=0
  const implContract = StorageContract.attach(impl);
  const transaction = await implContract.populateTransaction.initialize(
    4718592000, // minimumDiff 5 * 3 * 3600 * 1024 * 1024 / 12 = 4718592000 for 5 replicas that can have 1M IOs in one epoch
    1048576, // nonceLimit 1024 * 1024 = 1M samples and finish sampling in 1.3s with IO rate 6144 MB/s: 4k * 2(random checks) / 6144 = 1.3s
    3145728000000000000000n, // prepaidAmount - 50% * 2^39 / 131072 * 1500000Gwei, it also means 3145 ETH for half of the shard
    treasuryAddress, // treasury
    ownerAddress
  );
  const data = transaction.data;
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

  // fund 0.5 eth into the storage contract to give reward for empty mining
  const ethStorage = StorageContract.attach(ethStorageProxy.address);
  const tx = await ethStorage.sendValue({ value: hre.ethers.utils.parseEther("0.5") });
  await tx.wait();
  console.log("balance of " + ethStorage.address, await hre.ethers.provider.getBalance(ethStorage.address));
}

async function updateContract() {
  const impl = await deployCloneImpl();
  const EthStorageAdmin = await hre.ethers.getContractAt("IProxyAdmin", adminContractAddr);
  const tx = await EthStorageAdmin.upgradeAndCall(storageContractProxy, impl, "0x");
  await tx.wait();
  console.log("update contract success!")
}

async function main() {
  if(!storageContractProxy) {
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
