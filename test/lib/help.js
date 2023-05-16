const { web3 } = require("hardhat");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const {callPythonToGenreateMask, handlePyData} = require("./blob-poseidon")
const {generateG16Proof} = require("./prover")
const {printlog} = require("./print")

const BlobMap = new Map();
let maskList = [];
let maskIndex = 0;
let encodingKeyList = [];
let encodingKey_mod_list = [];
let sampleKvIdxList = [];
let sampleIdxInKvList = [];
let sampleIdxInKv_ru_list = [];
let decodedSampleList = [];
let encodedSampleList = [];

function getEncodedSampleList() {
  return encodedSampleList
}

const sleep = time => {
  return new Promise(resolve => setTimeout(resolve, time)
  )
}
async function getMask(encodingKey,sampleIdxInKv) {
  await sleep(3000)
  if (maskIndex == maskList.length){
    throw new Error("no enough mask")
  }
  maskIndex ++;
  let result =  maskList[maskIndex-1];
  if (result.length<66){
    maskList[maskIndex-1] = result.slice(0,2).concat("0").concat(result.slice(2,66))
  }
  return result;
    
}

function createBlob(kvIdx,begin_i,length) {
    let elements = new Array(length);
    for (let i = begin_i; i < begin_i + length; i++) {
        elements[i] = ethers.utils.formatBytes32String(i.toString());
      }
  
      let blob = ethers.utils.hexConcat(elements);
      BlobMap.set(kvIdx,blob);
      return blob;
}


async function getEncodingKey( kvIdx , miner, fromSC , StorageContract , merkleTreeContract){
    if (fromSC == true) {
        const encodingKey1 = await StorageContract.getEncodingKey(kvIdx, miner);
        return encodingKey1
    }
    const abiCoder = new ethers.utils.AbiCoder();
    let blob = BlobMap.get(kvIdx);
    const root = await merkleTreeContract.merkleRootMinTree(blob, 32);
    let rootArray = ethers.utils.arrayify(root);
    // convert bytes32 to bytes 24
    for (let i = 24; i < 32; i++) {
      rootArray[i] = 0;
    }
    const encodingKey = ethers.utils.keccak256(
      abiCoder.encode(["bytes32", "address", "uint256"], [ethers.utils.hexlify(rootArray), miner, kvIdx])
    );
    return encodingKey
}
    

function modEncodingKey(encodingKey){
    let modulusBn254 = "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001";
    let modulusBn254Big = ethers.BigNumber.from(modulusBn254)
    let encodingKeyBig = ethers.BigNumber.from(encodingKey) 
    return encodingKeyBig.mod(modulusBn254Big);
}

async function getSampleIdxByHashWithMask(StorageContract, startShardId, nextHash0 , Mask){
  let [nextSampleIdx,kvIdx,sampleIdxInKv] = await StorageContract.getSampleIdx(startShardId, nextHash0)
  sampleIdxInKv = sampleIdxInKv.toNumber();
  let sampleKvIdx = kvIdx.toNumber();
  let blobData = BlobMap.get(sampleKvIdx);
  let blobArray = ethers.utils.arrayify(blobData);

  let decodedSample = ethers.BigNumber.from(blobArray.slice(sampleIdxInKv* 32, (sampleIdxInKv + 1) * 32));
  let encodedSample = ethers.BigNumber.from(Mask).xor(decodedSample);
  return [sampleKvIdx, sampleIdxInKv,decodedSample, encodedSample];
}

async function getSampleIdxByHash(StorageContract, startShardId, nextHash0 , miner){
  let [nextSampleIdx,kvIdx,sampleIdxInKv] = await StorageContract.getSampleIdx(startShardId, nextHash0)
  sampleIdxInKv = sampleIdxInKv.toNumber();
  let sampleIdxInKvStr = sampleIdxInKv.toString();
  let sampleKvIdx = kvIdx.toNumber();
  let blobData = BlobMap.get(sampleKvIdx);
  let blobArray = ethers.utils.arrayify(blobData);

  let encodingKey = await getEncodingKey(kvIdx,miner,true,StorageContract,null)
  callPythonToGenreateMask(encodingKey,sampleIdxInKvStr,handlePyData(maskList,sampleIdxInKv_ru_list,encodingKey_mod_list))
  let Mask = await getMask(encodingKey,sampleIdxInKv);

  let decodedSample = ethers.BigNumber.from(blobArray.slice(sampleIdxInKv* 32, (sampleIdxInKv + 1) * 32));
  let encodedSample = ethers.BigNumber.from(Mask).xor(decodedSample);
  return [encodingKey ,sampleKvIdx, sampleIdxInKv,decodedSample, encodedSample];
}

async function getNextHash0(StorageContract,hash0,encodedSample){
  let nextHash0 = await StorageContract.getNextHash0(hash0,encodedSample);
  return nextHash0;
}

async function getInitHash0(StorageContract,blockNumber,miner,nonce){
  let initHash0 = await StorageContract.getInitHash0(blockNumber,miner,nonce);
  return initHash0;
}

async function execAllSamples(StorageContract, randomChecks, blockNumber,miner,nonce , startShardId){
  let initHash0 = await getInitHash0(StorageContract,blockNumber,miner,nonce);
  let hash0 = initHash0
  for (let i=0 ; i< randomChecks;i++){
    let [encodingkey , sampleKvIdx, sampleIdxInKv,decodedSample, encodedSample] = await getSampleIdxByHash(StorageContract,startShardId,hash0, miner)
    encodingKeyList.push(encodingkey);
    sampleKvIdxList.push(sampleKvIdx);
    sampleIdxInKvList.push(sampleIdxInKv);
    decodedSampleList.push(decodedSample);
    encodedSampleList.push (encodedSample);
    hash0 = await getNextHash0(StorageContract,hash0, encodedSample);
  }
  return hash0;
}

async function getMerkleProof(sampleKvIdx,sampleIdxInKv,decodedSampleData,StorageContract,MerkleLibContract){
  let blob = BlobMap.get(sampleKvIdx)
  let chunkSize = 32
  let nChunkBits = 8 // 2^8 = 256  ==> 256 * 32 = 8096
  let merkleProof = await MerkleLibContract.getProof(blob, chunkSize, nChunkBits, sampleIdxInKv);
  const root = await MerkleLibContract.merkleRootMinTree(blob, 32);
  expect(await MerkleLibContract.verify(decodedSampleData, sampleIdxInKv, root, merkleProof)).to.equal(true);
  return [root,merkleProof]
}

async function getSampleProof(root,merkleProof,decodeProof,encodingKey,sampleIdxInKv,decodedSampleData,Mask,StorageContract) {
  expect(await StorageContract.decodeSample(decodeProof, encodingKey, sampleIdxInKv, Mask)).to.equal(true);

  const abiCoder = new ethers.utils.AbiCoder();
  const integrityProof = abiCoder.encode(
    [
      "tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))",
      "uint256",
      "tuple(bytes32, bytes32, bytes32[])",
    ],
    [decodeProof, Mask, [decodedSampleData, root, merkleProof]]
  );

  return integrityProof
}

async function getIntegrityProof(decodeProof,Mask,encodingKey,sampleKvIdx,sampleIdxInKv,decodedSampleData,StorageContract,MerkleLibContract){
  let [root,merkleProof] = await getMerkleProof(sampleKvIdx,sampleIdxInKv,decodedSampleData,StorageContract,MerkleLibContract);
  let integrityProof = await getSampleProof(root,merkleProof, decodeProof,encodingKey,sampleIdxInKv,decodedSampleData,Mask,StorageContract)
   return integrityProof
}

async function generateDecodeProofs(){
  let g16proofs = [];
  for (let i = 0; i <encodingKey_mod_list.length;i++){
    let encodingKeyIn = encodingKey_mod_list[i]
    let xIn = sampleIdxInKv_ru_list[i]
    
    printlog("<<gen the %dth g16proof start>>",i)
    let key = "th generate g16 proof time cost "
    key = i.toString() + key;
    console.time(key)
    let [g16proof,inputs] = await generateG16Proof({encodingKeyIn,xIn});
    console.timeEnd(key)

    if (maskList[i].length<66){
      maskList[i] = maskList[i].slice(0,2).concat("0").concat(maskList[i].slice(2,66))
    }
    expect(ethers.BigNumber.from(inputs.signals[2]).toHexString()).to.eq(maskList[i])
    printlog("<<gen the %dth g16proof end>>",i)
    g16proofs.push(g16proof)
  }
  return g16proofs;
}

async function getAllIntegrityProofs(StorageContract,MerklelibContract){

  let decodeProofList = await generateDecodeProofs();
  let proofs = [];
  let currentIndex = 0;

  printlog("start to generate integrity proof")
  for (currentIndex;currentIndex<maskList.length;currentIndex++){
    let proof = await getIntegrityProof(
      decodeProofList[currentIndex],
      maskList[currentIndex],
      encodingKeyList[currentIndex],
      sampleKvIdxList[currentIndex],
      sampleIdxInKvList[currentIndex],
      decodedSampleList[currentIndex],
      StorageContract,
      MerklelibContract
    )
    proofs.push(proof)
  }
  return proofs;
}

exports.getSampleIdxByHash = getSampleIdxByHash
exports.modEncodingKey = modEncodingKey
exports.getEncodingKey = getEncodingKey
exports.createBlob = createBlob
exports.getMerkleProof = getMerkleProof
exports.getIntegrityProof = getIntegrityProof
exports.getSampleIdxByHashWithMask = getSampleIdxByHashWithMask
exports.execAllSamples = execAllSamples
exports.getAllIntegrityProofs = getAllIntegrityProofs
exports.getInitHash0 = getInitHash0
exports.getEncodedSampleList = getEncodedSampleList
exports.printlog = printlog