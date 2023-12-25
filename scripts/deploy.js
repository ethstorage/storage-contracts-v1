// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
  let StorageContract = await hre.ethers.getContractFactory("TestEthStorageContractKZG");
  const startTime = Math.floor(new Date().getTime() / 1000);
  
  // refer to https://docs.google.com/spreadsheets/d/11DHhSang1UZxIFAKYw6_Qxxb-V40Wh1lsYjY2dbIP5k/edit#gid=0
  let storageContract = await StorageContract.deploy(
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
    4194304000000000000000n, // prepaidAmount - 50% * 2 * 1024^4 / 131072 * 500000Gwei, it also means 4194 ETH for half of the shard
    { gasPrice: 30000000000 }
  );

  storageContract = await storageContract.waitForDeployment();
  const addr = await storageContract.getAddress();
  console.log("storage contract address is ", addr);

  const blockNumber = (await storageContract.deploymentTransaction()).blockNumber;
  console.log(
    "deployed in block number",
    blockNumber,
    "at",
    new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })
  );
  // fund 20 eth into the storage contract to give reward for empty mining
  const tx = await storageContract.sendValue({ value: hre.ethers.parseEther("20") });
  await tx.wait();
  console.log("balance of " + addr, await hre.ethers.provider.getBalance(addr));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
