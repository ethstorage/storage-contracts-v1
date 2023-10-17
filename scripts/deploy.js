const hre = require("hardhat");

async function main() {
  let StorageContract = await hre.ethers.getContractFactory("TestEthStorageContractKZG");
  const startTime = Math.floor(new Date().getTime() / 1000);

  let storageContract = await StorageContract.deploy(
    [
      17, // maxKvSizeBits, 131072
      30, // shardSizeBits ~ 1G
      2, // randomChecks
      10000000, // minimumDiff 10000000 / 60 = 16,666 sample/s is enable to mine, and one AX101 can provide 1M/12 = 83,333 sample/s power
      60, // cutoff, means 1 minute for testnet and may need to change longer later
      1024, // diffAdjDivisor
      100, // treasuryShare, means 1%
    ],
    startTime, // startTime
    2000000000000, // storageCost - 2000Gwei forever per blob - https://ethresear.ch/t/ethstorage-scaling-ethereum-storage-via-l2-and-da/14223/6#incentivization-for-storing-m-physical-replicas-1
    340282365167313208607671216367074279424n, // dcfFactor, it mean 0.85 for yearly discount
    1048576, // nonceLimit 1024 * 1024 = 1M samples and finish sampling in 1.3s with IO rate 6144 MB/s: 4k * 2(random checks) / 6144 = 1.3s
    "0x0000000000000000000000000000000000000000", // treasury
    8192000000000000, // prepaidAmount - ~ 50% discount, 4096 blob cost for 1G data
    { gasPrice: 30000000000 }
  );
  await storageContract.deployed();
  console.log("storage contract address is ", storageContract.address);

  // fund 10 eth into the storage contract to give reward for empty mining
  const tx = await storageContract.sendValue({ value: ethers.utils.parseEther("10") });
  await tx.wait();
  console.log("balance of " + storageContract.address, await hre.ethers.provider.getBalance(storageContract.address));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
