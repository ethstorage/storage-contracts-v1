const hre = require("hardhat");

async function main() {
  let StorageContract = await hre.ethers.getContractFactory("TestEthStorageContractKZG");
  let storageContract = await StorageContract.deploy(
    [
      17, // maxKvSizeBits
      30, // shardSizeBits ~ 1G
      2, // randomChecks
      1000000, // minimumDiff
      60, // cutoff
      1024, // diffAdjDivisor
      100, // treasuryShare
    ],
    0, // startTime
    0, // storageCost
    0, // dcfFactor
    1048576, // nonceLimit
    "0x0000000000000000000000000000000000000000", // treasury
    0 // prepaidAmount
  );
  await storageContract.deployed();
  console.log("storage contract address is ", storageContract.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
