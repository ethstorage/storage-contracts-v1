const hre = require("hardhat");

let ownerAddress = null;
let treasuryAddress = null;
const adminContractAddr = "0x11aceF404143514dbe0C1477250605646754F9e6";
const storageContractProxy = "0x804C520d3c084C805E37A35E90057Ac32831F96f";
const gasPrice = null;

async function deployContract() {
  const [deployer] = await hre.ethers.getSigners();
  ownerAddress = deployer.address;
  treasuryAddress = deployer.address;

  const StorageContract = await hre.ethers.getContractFactory("TestEthStorageContractKZG");
  // refer to https://docs.google.com/spreadsheets/d/11DHhSang1UZxIFAKYw6_Qxxb-V40Wh1lsYjY2dbIP5k/edit#gid=0
  const implContract = await StorageContract.deploy({ gasPrice: gasPrice });
  await implContract.deployed();
  const impl = implContract.address;
  console.log("storage impl address is ", impl);

  const data = implContract.interface.encodeFunctionData("initialize", [
    treasuryAddress, // treasury
    ownerAddress
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

  // fund 0.5 eth into the storage contract to give reward for empty mining
  const ethStorage = StorageContract.attach(ethStorageProxy.address);
  const tx = await ethStorage.sendValue({ value: hre.ethers.utils.parseEther("0.5") });
  await tx.wait();
  console.log("balance of " + ethStorage.address, await hre.ethers.provider.getBalance(ethStorage.address));

  const startTime = await ethStorage.startTime();
  console.log("start time is", startTime);
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
