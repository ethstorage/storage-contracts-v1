const { web3 } = require("hardhat");
const { expect } = require("chai");
const { ethers } = require("hardhat");

/* declare const key */
const key1 = "0x0000000000000000000000000000000000000000000000000000000000000001";
const key2 = "0x0000000000000000000000000000000000000000000000000000000000000002";
const key3 = "0x0000000000000000000000000000000000000000000000000000000000000003";

describe("EthStorageContract Test", function () {
  it("decode-inclusive-8k-blob-test", async function () {
    const EthStorageContract = await ethers.getContractFactory("TestEthStorageContract");
    const sc = await EthStorageContract.deploy(
      [
        13, // maxKvSizeBits
        14, // shardSizeBits
        1, // randomChecks
        1, // minimumDiff
        60, // targetIntervalSec
        40, // cutoff
        1024, // diffAdjDivisor
        0, // treasuryShare
      ],
      0, // startTime
      0, // storageCost
      0, // dcfFactor
      1, // nonceLimit
      "0x0000000000000000000000000000000000000000", // treasury
      0 // prepaidAmount
    );
    await sc.deployed();

    let elements = new Array(256);
    // let blob = "0x";

    for (let i = 0; i < 256; i++) {
      elements[i] = ethers.utils.formatBytes32String(i.toString());
    }

    let blob = ethers.utils.hexConcat(elements);
    sc.put(key1, blob);

    const encodingKey = "0x1122000000000000000000000000000000000000000000000000000000000000";
    const sampleIdxInKv = 123;
    const mask = "0x301b9cec8aae1155d883c48308dbd2f24e54aff21bfbd7b3d1afecb5507bf521";
    const proof = [
      [
        "0x090f3e4a06c0ed38dcb3a37315500c141445e34a5cb337cb2056f7f31901dc58",
        "0x0589ecedde0c8c58b8840aa673ad737b5b6a2db6953a058d8837475bba0ba7bb",
      ],
      [
        [
          "0x05299703ffdb8cc84182e8ff9e25f52e37e28eb394a63ce4868d5468e6782b6b",
          "0x17639172d28071634a2c52e1141b749561ed36ed18afe1d01f4ceb8a9ecc5bcd",
        ],
        [
          "0x1160394a5486727ab770b6eb79b48b401ce217f94935a6b887ec29d162cb29f7",
          "0x2931be7c62deb504103a7675651a469e07911ba8ea3dc26cca7402a5b4dd9410",
        ],
      ],
      [
        "0x2a43c2db08a6da5a69f2e151dd0b4ff207de82f2734936945611c03f607276c9",
        "0x21d11d759864978d12ee06a093d56941a79de611e9df633c404770d70c2fd5a7",
      ],
    ];
    expect(await sc.decodeSample(proof, encodingKey, sampleIdxInKv, mask)).to.equal(true);
  });
});
