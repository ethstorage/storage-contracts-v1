const hre = require("hardhat");

const adminContractAddr = null;
const storageContractProxy = null;

async function deployContract() {
  const startTime = Math.floor(new Date().getTime() / 1000);

  const StorageContract = await hre.ethers.getContractFactory("TestEthStorageContractKZG");
  // refer to https://docs.google.com/spreadsheets/d/11DHhSang1UZxIFAKYw6_Qxxb-V40Wh1lsYjY2dbIP5k/edit#gid=0
  const implContract = await StorageContract.deploy({ gasPrice: 30000000000 });
  await implContract.deployed();
  const impl = implContract.address;
  console.log("storage impl address is ", impl);

  const EthStorageAdmin = await hre.ethers.getContractFactory("EthStorageAdmin");
  const adminContract = await EthStorageAdmin.deploy();
  await adminContract.deployed();
  console.log("storage admin address is ", adminContract.address);

  const transaction = await implContract.populateTransaction.initialize(
    [
      17, // maxKvSizeBits, 131072
      41, // shardSizeBits ~ 2T
      2, // randomChecks
      10000000, // minimumDiff 10000000 / 10800 = 925 sample/s is enable to mine, and one AX101 can provide 1M/12 = 83,333 sample/s power
      10800, // cutoff, means target internal is 12 hours 
      1024, // diffAdjDivisor
      100, // treasuryShare, means 1%
    ],
    startTime, // startTime
    500000000000000, // storageCost - 500,000Gwei forever per blob - https://ethresear.ch/t/ethstorage-scaling-ethereum-storage-via-l2-and-da/14223/6#incentivization-for-storing-m-physical-replicas-1
    340282366367469178095360967382638002176n, // dcfFactor, it mean 0.95 for yearly discount
    1048576, // nonceLimit 1024 * 1024 = 1M samples and finish sampling in 1.3s with IO rate 6144 MB/s: 4k * 2(random checks) / 6144 = 1.3s
    "0x0000000000000000000000000000000000000000", // treasury
    4194304000000000000000n
  );
  const data = transaction.data;
  const EthStorageUpgradeableProxy = await hre.ethers.getContractFactory("EthStorageUpgradeableProxy");
  const ethStorageProxy = await EthStorageUpgradeableProxy.deploy(impl, adminContract.address, data);
  await ethStorageProxy.deployed();

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
  const tx = await ethStorage.sendValue({ value: hre.ethers.utils.parseEther("0.020") });
  await tx.wait();
  console.log("balance of " + ethStorage.address, await hre.ethers.provider.getBalance(ethStorage.address));
}

async function updateContract() {
    const StorageContract = await hre.ethers.getContractFactory("TestEthStorageContractKZG");
    const implContract = await StorageContract.deploy({ gasPrice: 30000000000 });
    await implContract.deployed();
    const impl = implContract.address;
    console.log("storage impl address is ", impl);

    const EthStorageAdmin = await hre.ethers.getContractFactory("EthStorageAdmin");
    const adminContract = await EthStorageAdmin.attach(adminContractAddr);
    const tx = await adminContract.upgrade(storageContractProxy, impl);
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
