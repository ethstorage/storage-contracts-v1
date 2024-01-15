const hre = require("hardhat");

let ownerAddress = null;
const adminContractAddr = null;
const storageContractProxy = null;
const gasPrice = 30000000000;

async function deployContract() {
  const startTime = Math.floor(new Date().getTime() / 1000);

  const [deployer] = await hre.ethers.getSigners();
  ownerAddress = deployer.address;

  const StorageContract = await hre.ethers.getContractFactory("TestEthStorageContractKZG");
  // refer to https://docs.google.com/spreadsheets/d/11DHhSang1UZxIFAKYw6_Qxxb-V40Wh1lsYjY2dbIP5k/edit#gid=0
  const implContract = await StorageContract.deploy({ gasPrice: gasPrice });
  await implContract.deployed();
  const impl = implContract.address;
  console.log("storage impl address is ", impl);

  const transaction = await implContract.populateTransaction.initialize(
    [
      17, // maxKvSizeBits, 131072
      39, // shardSizeBits ~ 512G
      2, // randomChecks
      9437184000, // minimumDiff 10 * 3 * 3600 * 1024 * 1024 / 12 = 9437184000 for ten replica that can have 1M IOs in one epoch
      7200, // cutoff = 2/3 * target internal (3 hours), 3 * 3600 * 2/3
      32, // diffAdjDivisor
      100, // treasuryShare, means 1%
    ],
    startTime, // startTime
    500000000000000, // storageCost - 500,000Gwei forever per blob - https://ethresear.ch/t/ethstorage-scaling-ethereum-storage-via-l2-and-da/14223/6#incentivization-for-storing-m-physical-replicas-1
    340282366367469178095360967382638002176n, // dcfFactor, it mean 0.95 for yearly discount
    1048576, // nonceLimit 1024 * 1024 = 1M samples and finish sampling in 1.3s with IO rate 6144 MB/s: 4k * 2(random checks) / 6144 = 1.3s
    ownerAddress, // treasury
    1048576000000000000000n // prepaidAmount - 50% * 2^39 / 131072 * 500000Gwei, it also means 1048 ETH for half of the shard
  );
  const data = transaction.data;
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

  // fund 20 eth into the storage contract to give reward for empty mining
  const ethStorage = StorageContract.attach(ethStorageProxy.address);
  const tx = await ethStorage.sendValue({ value: hre.ethers.utils.parseEther("0.00020") });
  await tx.wait();
  console.log("balance of " + ethStorage.address, await hre.ethers.provider.getBalance(ethStorage.address));
}

async function updateContract() {
    const StorageContract = await hre.ethers.getContractFactory("TestEthStorageContractKZG");
    const implContract = await StorageContract.deploy({ gasPrice: gasPrice });
    await implContract.deployed();
    const impl = implContract.address;
    console.log("storage impl address is ", impl);

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
