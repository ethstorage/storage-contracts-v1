const { web3 } = require("hardhat");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const crypto = require("crypto");

var hexlify4 = (x) => ethers.utils.hexZeroPad(ethers.utils.hexlify(x), 4);
describe("MerkleLib Test", function () {
  it("full zero data verify", async function () {
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let data = new Array(64 * 8).fill(0);
    let root = await ml.merkleRoot(data, 64, 3);
    for (let i = 0; i < 8; i++) {
      let proof = await ml.getProof(data, 64, 3, i);
      let chunkData = data.slice(i * 64, (i + 1) * 64);
      expect(await ml.verify(chunkData, i, root, proof)).to.equal(true);
    }
  });

  it("full random data verify", async function () {
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let data = crypto.randomBytes(64 * 8);
    let root = await ml.merkleRoot(data, 64, 3);
    for (let i = 0; i < 8; i++) {
      let proof = await ml.getProof(data, 64, 3, i);
      let chunkData = data.slice(i * 64, (i + 1) * 64);
      expect(await ml.verify(chunkData, i, root, proof)).to.equal(true);
    }
  });

  it("8K data testing", async function () {
    // 4K as chunk
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    const d = crypto.randomBytes(4096 * 2);
    const root = await ml.merkleRoot(d, 4096, 1);
    const leftSliceProof = await ml.getProof(d, 4096, 1, 0);
    expect(await ml.verify(d.slice(0, 4096), 0, root, leftSliceProof)).to.be.true;
    const rightSliceProof = await ml.getProof(d, 4096, 1, 1);
    expect(await ml.verify(d.slice(4096, 8192), 1, root, rightSliceProof)).to.be.true;
  });

  it("partial random data verify0", async function () {
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let data = crypto.randomBytes(8);
    let root = await ml.merkleRoot(data, 64, 3);
    for (let i = 0; i < 8; i++) {
      let proof = await ml.getProof(data, 64, 3, i);
      let chunkData = data.slice(i * 64, (i + 1) * 64);
      if (chunkData.length == 0) {
        break;
      }
      expect(await ml.verify(chunkData, i, root, proof)).to.equal(true);
    }
  });

  it("partial random data verify1", async function () {
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let data = crypto.randomBytes(64 * 3 + 16);
    let root = await ml.merkleRoot(data, 64, 3);
    for (let i = 0; i < 8; i++) {
      let proof = await ml.getProof(data, 64, 3, i);
      let chunkData = data.slice(i * 64, (i + 1) * 64);
      if (chunkData.length == 0) {
        break;
      }
      expect(await ml.verify(chunkData, i, root, proof)).to.equal(true);
    }
  });

  it("partial random data verify2", async function () {
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let data = crypto.randomBytes(64 * 6 + 48);
    let root = await ml.merkleRoot(data, 64, 3);
    for (let i = 0; i < 8; i++) {
      let proof = await ml.getProof(data, 64, 3, i);
      let chunkData = data.slice(i * 64, (i + 1) * 64);
      if (chunkData.length == 0) {
        break;
      }
      expect(await ml.verify(chunkData, i, root, proof)).to.equal(true);
    }
  });

  it("gas for 4K chunk and 32K kv", async function () {
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    // await ml.merkleRootNoView(crypto.randomBytes(4096 * 8), 4096, 3);
    await ml.merkleRootNoView(crypto.randomBytes(4096), 4096, 3);
    await ml.merkleRootNoView(crypto.randomBytes(4096 * 2), 4096, 3);
    await ml.merkleRootNoView(crypto.randomBytes(4096 * 3), 4096, 3);

    await ml.keccak256NoView(crypto.randomBytes(4096 * 3));
  });

  it("should forbid illegal parameter", async function () {
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let data = crypto.randomBytes(64 * 6 + 48);
    let root = await ml.merkleRoot(data, 64, 3);

    // trys to get a out-of-bound index proof
    await expect(ml.getProof(data, 64, 3, 10)).to.be.revertedWith("index out of scope");

    let proof = await ml.getProof(data, 64, 3, 0);
    expect(await ml.verify(data.slice(0, 64), 0, root, proof)).to.equal(true);
    // out of bound index
    await expect(ml.verify(data.slice(0, 64), 8, root, proof)).to.be.revertedWith("chunkId overflows");
    await expect(ml.verify(data.slice(0, 64), 10, root, proof)).to.be.revertedWith("chunkId overflows");
  });

  it("check getMaxLeafsNum()", async function () {
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let leafsNum = await ml.getMaxLeafsNum(8192, 2048);
    expect(leafsNum).to.eq(4);

    leafsNum = await ml.getMaxLeafsNum(4096, 2048);
    expect(leafsNum).to.eq(2);

    leafsNum = await ml.getMaxLeafsNum(6000, 2048);
    expect(leafsNum).to.eq(4);

    leafsNum = await ml.getMaxLeafsNum(3000, 2048);
    expect(leafsNum).to.eq(2);

    leafsNum = await ml.getMaxLeafsNum(12288, 2048);
    expect(leafsNum).to.eq(8);
  });
});
