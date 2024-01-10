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
      elements[i] = ethers.utils.formatBytes32String(i.toString());
    }

    let blob = ethers.utils.hexConcat(elements);
    this.BlobMap.set(kvIdx, blob);
    printlog("kvIdx-%d blob length: %d", kvIdx, blob.length);
    return blob;
  }

  createRandomBlob(kvIdx, length) {
    length = 32 * length;
    let array = ethers.utils.randomBytes(length);
    let blob = ethers.utils.hexlify(array);
    printlog("kvIdx-%d blob length: %d", kvIdx, blob.length);

    this.BlobMap.set(kvIdx, blob);
    return blob;
  }

  async getEncodingKey(kvIdx, miner, fromSC) {
    if (fromSC == true) {
      const encodingKey1 = await this.StorageContract.getEncodingKey(kvIdx, miner);
      return encodingKey1;
    }
    const abiCoder = new ethers.utils.AbiCoder();
    let blob = this.BlobMap.get(kvIdx);
    const root = await this.MerkleLibContract.merkleRootMinTree(blob, 32);
    let rootArray = ethers.utils.arrayify(root);
    // convert bytes32 to bytes 24
    for (let i = 24; i < 32; i++) {
      rootArray[i] = 0;
    }
    const encodingKey = ethers.utils.keccak256(
      abiCoder.encode(["bytes32", "address", "uint256"], [ethers.utils.hexlify(rootArray), miner, kvIdx])
    );
    return encodingKey;
  }

  modEncodingKey(encodingKey) {
    let modulusBn254 = "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001";
    let modulusBn254Big = ethers.BigNumber.from(modulusBn254);
    let encodingKeyBig = ethers.BigNumber.from(encodingKey);
    return encodingKeyBig.mod(modulusBn254Big);
  }

  async getSampleIdxByHashWithMask(startShardId, nextHash0, Mask) {
    let [nextSampleIdx, kvIdx, sampleIdxInKv] = await this.StorageContract.getSampleIdx0(startShardId, nextHash0);
    sampleIdxInKv = sampleIdxInKv.toNumber();
    let sampleKvIdx = kvIdx.toNumber();
    let blobData = this.BlobMap.get(sampleKvIdx);
    let blobArray = ethers.utils.arrayify(blobData);

    let decodedSample = ethers.BigNumber.from(blobArray.slice(sampleIdxInKv * 32, (sampleIdxInKv + 1) * 32));
    let encodedSample = ethers.BigNumber.from(Mask).xor(decodedSample);
    return [sampleKvIdx, sampleIdxInKv, decodedSample, encodedSample];
  }

  async getSampleIdxByHash(startShardId, nextHash0, miner) {
    let [nextSampleIdx, kvIdx, sampleIdxInKv] = await this.StorageContract.getSampleIdx0(startShardId, nextHash0);
    sampleIdxInKv = sampleIdxInKv.toNumber();
    let sampleIdxInKvStr = sampleIdxInKv.toString();
    let sampleKvIdx = kvIdx.toNumber();
    let blobData = this.BlobMap.get(sampleKvIdx);
    let blobArray = ethers.utils.arrayify(blobData);

    let encodingKey = await this.getEncodingKey(kvIdx, miner, true);
    await callPythonToGenreateMask(
      encodingKey,
      sampleIdxInKvStr,
      handlePyData(this.maskList, this.sampleIdxInKvRuList, this.encodingKeyModList)
    );
    let Mask = this.getMask();

    let decodedSample = ethers.BigNumber.from(blobArray.slice(sampleIdxInKv * 32, (sampleIdxInKv + 1) * 32));
    let encodedSample = ethers.BigNumber.from(Mask).xor(decodedSample);
    return [encodingKey, sampleKvIdx, sampleIdxInKv, decodedSample, encodedSample];
  }

  async getNextHash0(hash0, encodedSample) {
    let nextHash0 = await this.StorageContract.getNextHash0(hash0, encodedSample);
    return nextHash0;
  }

  async getInitHash0(blockNumber, miner, nonce) {
    let initHash0 = await this.StorageContract.getInitHash0(blockNumber, miner, nonce);
    return initHash0;
  }

  async execAllSamples(randomChecks, blockNumber, miner, nonce, startShardId) {
    let initHash0 = await this.getInitHash0(blockNumber, miner, nonce);
    let hash0 = initHash0;
    for (let i = 0; i < randomChecks; i++) {
      let [encodingkey, sampleKvIdx, sampleIdxInKv, decodedSample, encodedSample] = await this.getSampleIdxByHash(
        startShardId,
        hash0,
        miner
      );
      this.encodingKeyList.push(encodingkey);
      this.sampleKvIdxList.push(sampleKvIdx);
      this.sampleIdxInKvList.push(sampleIdxInKv);
      this.decodedSampleList.push(decodedSample);
      this.encodedSampleList.push(encodedSample);
      hash0 = await this.getNextHash0(hash0, encodedSample);
    }
    return hash0;
  }

  async getMerkleProof(sampleKvIdx, sampleIdxInKv, decodedSampleData) {
    let blob = this.BlobMap.get(sampleKvIdx);
    let chunkSize = 32;
    let nChunkBits = 8; // 2^8 = 256  ==> 256 * 32 = 8096
    let merkleProof = await this.MerkleLibContract.getProof(blob, chunkSize, nChunkBits, sampleIdxInKv);
    const root = await this.MerkleLibContract.merkleRootMinTree(blob, 32);
    expect(await this.MerkleLibContract.verify(decodedSampleData, sampleIdxInKv, root, merkleProof)).to.equal(true);
    return [root, merkleProof];
  }

  async getSampleProof(root, merkleProof, decodeProof, encodingKey, sampleIdxInKv, decodedSampleData, Mask) {
    expect(await this.StorageContract.decodeSample(decodeProof, encodingKey, sampleIdxInKv, Mask)).to.equal(true);

    const abiCoder = new ethers.utils.AbiCoder();
    const integrityProof = abiCoder.encode(
      [
        "tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))",
        "uint256",
        "tuple(bytes32, bytes32, bytes32[])",
      ],
      [decodeProof, Mask, [decodedSampleData, root, merkleProof]]
    );

    return integrityProof;
  }

  async getIntegrityProof(decodeProof, Mask, encodingKey, sampleKvIdx, sampleIdxInKv, decodedSampleData) {
    let [root, merkleProof] = await this.getMerkleProof(sampleKvIdx, sampleIdxInKv, decodedSampleData);
    let integrityProof = await this.getSampleProof(
      root,
      merkleProof,
      decodeProof,
      encodingKey,
      sampleIdxInKv,
      decodedSampleData,
      Mask
    );
    return integrityProof;
  }

  async getIntegrityProof2(decodeProof, Mask, encodingKey, sampleKvIdx, sampleIdxInKv, decodedSampleData) {
    let [root, merkleProof] = await this.getMerkleProof(sampleKvIdx, sampleIdxInKv, decodedSampleData);
    expect(await this.StorageContract.decodeSample(decodeProof, encodingKey, sampleIdxInKv, Mask)).to.equal(true);

    const abiCoder = new ethers.utils.AbiCoder();
    const decodeProofData = abiCoder.encode(
        ["tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))"],
        [decodeProof]
    );
    const inclusiveProofData = abiCoder.encode(
        ["tuple(bytes32, bytes32, bytes32[])"],
        [[decodedSampleData, root, merkleProof]]
    );
    return {
      decodeProof: decodeProofData,
      inclusiveProof: inclusiveProofData
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
      expect(ethers.BigNumber.from(inputs.signals[2]).toHexString()).to.eq(this.maskList[i]);
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
      let proof = await this.getIntegrityProof(
        decodeProofList[currentIndex],
        this.maskList[currentIndex],
        this.encodingKeyList[currentIndex],
        this.sampleKvIdxList[currentIndex],
        this.sampleIdxInKvList[currentIndex],
        this.decodedSampleList[currentIndex]
      );
      proofs.push(proof);
    }
    return proofs;
  }
}

exports.TestState = TestState;
