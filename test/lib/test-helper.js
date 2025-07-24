const { expect } = require("chai");
const { ethers } = require("hardhat");
const { callPythonToGenreateMask, handlePyData } = require("./blob-poseidon");
const { generateG16Proof } = require("./prover");
const { printlog } = require("./print");

class TestState {
  constructor(StorageContract, MerkleLibContract) {
    this.StorageContract = StorageContract;
    this.MerkleLibContract = MerkleLibContract;
    this.BlobMap = new Map();
    this.maskList = [];
    this.maskIndex = 0;
    this.encodingKeyList = [];
    this.encodingKeyModList = [];
    this.sampleKvIdxList = [];
    this.sampleIdxInKvList = [];
    this.sampleIdxInKvRuList = [];
    this.decodedSampleList = [];
    this.encodedSampleList = [];
  }

  getEncodedSampleList() {
    return this.encodedSampleList;
  }

  getMaskList() {
    return this.maskList;
  }

  getMask() {
    if (this.maskIndex == this.maskList.length) {
      throw new Error("no enough mask");
    }
    this.maskIndex++;
    let result = this.maskList[this.maskIndex - 1];
    if (result.length < 66) {
      this.maskList[this.maskIndex - 1] = result.slice(0, 2).concat("0").concat(result.slice(2, 66));
    }
    return result;
  }

  createBlob(kvIdx, beginIdx, length) {
    let elements = new Array(length);
    for (let i = beginIdx; i < beginIdx + length; i++) {
      elements[i] = ethers.encodeBytes32String(i.toString());
    }

    let blob = ethers.concat(elements);
    this.BlobMap.set(kvIdx, blob);
    printlog("kvIdx-%d blob length: %d", kvIdx, blob.length);
    return blob;
  }

  createRandomBlob(kvIdx, length) {
    length = 32 * length;
    let array = ethers.randomBytes(length);
    let blob = ethers.hexlify(array);
    printlog("kvIdx-%d blob length: %d", kvIdx, blob.length);

    this.BlobMap.set(kvIdx, blob);
    return blob;
  }

  async getEncodingKey(kvIdx, miner, fromSC) {
    if (fromSC == true) {
      const encodingKey1 = await this.StorageContract.getEncodingKey(kvIdx, miner);
      return encodingKey1;
    }
    const abiCoder = new ethers.AbiCoder();
    let blob = this.BlobMap.get(kvIdx);
    const root = await this.MerkleLibContract.merkleRootMinTree(blob, 32);
    let rootArray = ethers.getBytes(root);
    // convert bytes32 to bytes 24
    for (let i = 24; i < 32; i++) {
      rootArray[i] = 0;
    }
    const encodingKey = ethers.keccak256(
      abiCoder.encode(["bytes32", "address", "uint256"], [ethers.hexlify(rootArray), miner, kvIdx]),
    );
    return encodingKey;
  }

  modEncodingKey(encodingKey) {
    let modulusBn254 = "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001";
    let modulusBn254Big = ethers.toBigInt(modulusBn254);
    let encodingKeyBig = ethers.toBigInt(encodingKey);
    return encodingKeyBig.mod(modulusBn254Big);
  }

  async getSampleIdxByHashWithMask(startShardId, nextHash0, Mask) {
    let [, kvIdx, sampleIdxInKv] = await this.StorageContract["getSampleIdx(uint256,bytes32)"](startShardId, nextHash0);

    const sampleIdxInKvBig = ethers.toBigInt(sampleIdxInKv);
    const sampleKvIdxBig = ethers.toBigInt(kvIdx);

    let blobData = this.BlobMap.get(Number(sampleKvIdxBig));
    if (!blobData) {
      throw new Error(`No blob data found for kvIdx ${sampleKvIdxBig}`);
    }
    let blobArray = ethers.getBytes(blobData);

    let sampleBytes = blobArray.slice(Number(sampleIdxInKvBig) * 32, (Number(sampleIdxInKvBig) + 1) * 32);
    let decodedSample = ethers.toBigInt(ethers.hexlify(sampleBytes));
    let encodedSample = ethers.toBigInt(Mask) ^ decodedSample;
    return [sampleKvIdxBig, sampleIdxInKvBig, decodedSample, encodedSample];
  }

  async getSampleIdxByHash(startShardId, nextHash0, miner) {
    let [, kvIdx, sampleIdxInKv] = await this.StorageContract["getSampleIdx(uint256,bytes32)"](startShardId, nextHash0);
    const sampleIdxInKvBig = ethers.toBigInt(sampleIdxInKv);
    let sampleIdxInKvStr = sampleIdxInKv.toString();
    const sampleKvIdxBig = ethers.toBigInt(kvIdx);

    let blobData = this.BlobMap.get(Number(sampleKvIdxBig));
    if (!blobData) {
      throw new Error(`No blob data found for kvIdx ${sampleKvIdxBig}`);
    }
    let blobArray = ethers.getBytes(blobData);

    let encodingKey = await this.getEncodingKey(kvIdx, miner, true);
    await callPythonToGenreateMask(
      encodingKey,
      sampleIdxInKvStr,
      handlePyData(this.maskList, this.sampleIdxInKvRuList, this.encodingKeyModList),
    );
    let Mask = this.getMask();

    let sampleBytes = blobArray.slice(Number(sampleIdxInKvBig) * 32, (Number(sampleIdxInKvBig) + 1) * 32);
    let decodedSample = ethers.toBigInt(ethers.hexlify(sampleBytes));
    let encodedSample = ethers.toBigInt(Mask) ^ decodedSample;
    return [encodingKey, sampleKvIdxBig, sampleIdxInKvBig, decodedSample, encodedSample];
  }

  async getNextHash0(hash0, encodedSample) {
    let nextHash0 = await this.StorageContract.getNextHash0(hash0, encodedSample);
    return nextHash0;
  }

  async getInitHash0(randao, miner, nonce) {
    let initHash0 = await this.StorageContract.getInitHash0(randao, miner, nonce);
    return initHash0;
  }

  async execAllSamples(randomChecks, randao, miner, nonce, startShardId) {
    let initHash0 = await this.getInitHash0(randao, miner, nonce);
    let hash0 = initHash0;
    for (let i = 0; i < randomChecks; i++) {
      let [encodingkey, sampleKvIdx, sampleIdxInKv, decodedSample, encodedSample] = await this.getSampleIdxByHash(
        startShardId,
        hash0,
        miner,
      );
      this.encodingKeyList.push(encodingkey);
      this.sampleKvIdxList.push(sampleKvIdx);
      this.sampleIdxInKvList.push(sampleIdxInKv);
      this.decodedSampleList.push(decodedSample);
      this.encodedSampleList.push(encodedSample);
      const encodedSampleHex = ethers.toBeHex(encodedSample, 32);
      hash0 = await this.getNextHash0(hash0, encodedSampleHex);
    }
    return hash0;
  }

  async getMerkleProof(sampleKvIdx, sampleIdxInKv, decodedSampleData) {
    let blob = this.BlobMap.get(Number(sampleKvIdx));
    if (!blob) {
      throw new Error(`No blob data found for kvIdx ${sampleKvIdx}`);
    }
    const chunkSize = 32;
    const nChunkBits = 8; // 2^8 = 256  ==> 256 * 32 = 8096
    try {
      // Convert decodedSampleData to hex if it's a BigInt
      const decodedSampleHex =
        typeof decodedSampleData === "bigint" ? ethers.toBeHex(decodedSampleData, 32) : decodedSampleData;
      const merkleProofImmutable = await this.MerkleLibContract.getProof(blob, chunkSize, nChunkBits, sampleIdxInKv);
      let merkleProof = [...merkleProofImmutable];
      const root = await this.MerkleLibContract.merkleRootMinTree(blob, chunkSize);
      const verified = await this.MerkleLibContract.verify(decodedSampleHex, sampleIdxInKv, root, merkleProof);
      expect(verified).to.equal(true);
      return [root, merkleProof];
    } catch (error) {
      console.error("Error in getMerkleProof:", error);
      throw error;
    }
  }

  async getIntegrityProof(decodeProof, Mask, encodingKey, sampleKvIdx, sampleIdxInKv, decodedSampleData) {
    let [root, merkleProof] = await this.getMerkleProof(sampleKvIdx, sampleIdxInKv, decodedSampleData);

    const abiCoder = new ethers.AbiCoder();
    const decodeProofData = abiCoder.encode(
      ["tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))"],
      [decodeProof],
    );

    expect(await this.StorageContract.decodeSample(decodeProofData, encodingKey, sampleIdxInKv, Mask)).to.equal(true);
    const inclusiveProofData = abiCoder.encode(
      ["tuple(bytes32, bytes32, bytes32[])"],
      [[decodedSampleData, root, merkleProof]],
    );
    return {
      decodeProof: decodeProofData,
      inclusiveProof: inclusiveProofData,
    };
  }

  async generateDecodeProofs() {
    let g16proofs = [];
    for (let i = 0; i < this.encodingKeyModList.length; i++) {
      let encodingKeyIn = this.encodingKeyModList[i];
      let xIn = this.sampleIdxInKvRuList[i];

      printlog("<<gen the %dth g16proof start>>", i);
      let key = "th generate g16 proof time cost ";
      key = i.toString() + key;
      console.time(key);
      let [g16proof, inputs] = await generateG16Proof({ encodingKeyIn, xIn });
      console.timeEnd(key);

      if (this.maskList[i].length < 66) {
        this.maskList[i] = this.maskList[i].slice(0, 2).concat("0").concat(this.maskList[i].slice(2, 66));
      }
      expect(ethers.toBeHex(ethers.toBigInt(inputs.signals[2]), 32)).to.eq(this.maskList[i]);
      printlog("<<gen the %dth g16proof end>>", i);
      g16proofs.push(g16proof);
    }
    return g16proofs;
  }

  async getAllIntegrityProofs() {
    let decodeProofList = await this.generateDecodeProofs();
    let proofs = [];
    let currentIndex = 0;

    printlog("start to generate integrity proof");
    for (currentIndex; currentIndex < this.maskList.length; currentIndex++) {
      const Mask = this.maskList[currentIndex];
      const MaskHex = ethers.toBeHex(ethers.toBigInt(Mask), 32);
      const encodingKey = this.encodingKeyModList[currentIndex];
      const encodingKeyHex = ethers.toBeHex(ethers.toBigInt(encodingKey), 32);
      const decodedSample = this.decodedSampleList[currentIndex];
      const decodedSampleHex = ethers.toBeHex(decodedSample, 32);
      let proof = await this.getIntegrityProof(
        decodeProofList[currentIndex],
        MaskHex,
        encodingKeyHex,
        this.sampleKvIdxList[currentIndex],
        this.sampleIdxInKvList[currentIndex],
        decodedSampleHex,
      );
      proofs.push(proof);
    }
    return proofs;
  }
}

exports.TestState = TestState;
