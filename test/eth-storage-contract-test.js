const { expect } = require("chai");
const { ethers } = require("hardhat");
require("dotenv").config();

const { TestState } = require("./lib/test-helper");
const { printlog } = require("./lib/print");
const { generateRandaoProof } = require("./lib/prover");
const { keccak256 } = ethers.utils;

/* declare const key */
const key1 = "0x0000000000000000000000000000000000000000000000000000000000000001";
const key2 = "0x0000000000000000000000000000000000000000000000000000000000000002";
const key3 = "0x0000000000000000000000000000000000000000000000000000000000000003";
const ownerAddr = "0x0000000000000000000000000000000000000001";

async function deployCloneImpl(factory, address, params, minimumDiff, nonceLimit, prepaidAmount, treasury) {
  let types = [];
  let values = [];
  params.forEach(item => {
    types.push("uint256");
    values.push(item);
  });
  const data = ethers.utils.solidityPack(types, values);
  let tx = await factory.createCloneByAddress(address, data);
  tx = await tx.wait();
  const log = factory.interface.parseLog(tx.logs[0]);
  const impl = log.args[0];

  const TestEthStorageContract = await ethers.getContractFactory("TestEthStorageContract");
  const sc = TestEthStorageContract.attach(impl);
  await sc.initialize(minimumDiff, nonceLimit, prepaidAmount, treasury, ownerAddr);
  return sc;
}

describe("EthStorageContract Test", function () {
  let factory;
  let sc;
  beforeEach(async () => {
    const EthStorageCloneFactory = await ethers.getContractFactory("EthStorageCloneFactory");
    factory = await EthStorageCloneFactory.deploy();
    await factory.deployed();

    const EthStorageContract = await ethers.getContractFactory("TestEthStorageContract");
    sc = await EthStorageContract.deploy();
    await sc.deployed();
  });

  it("decode-8k-blob-test", async function () {
    sc = await deployCloneImpl(
        factory,
        sc.address,
        [
          0, // storageCost
          0, // dcfFactor
          0, // startTime
          1 << 13,
          13, // maxKvSizeBits
          14, // shardSizeBits
          14 - 13, //_config.shardSizeBits - _config.maxKvSizeBits,
          13 - 5, // _config.maxKvSizeBits - sampleSizeBits
          1, // randomChecks
          40, // cutoff
          1024, // diffAdjDivisor
          0, // treasuryShare
        ],
        1, // minimumDiff
        1, // nonceLimit
        0, // prepaidAmount
        "0x0000000000000000000000000000000000000000", // treasury
        ownerAddr
    );

    let elements = new Array(256);

    for (let i = 0; i < 256; i++) {
      elements[i] = ethers.utils.formatBytes32String(i.toString());
    }

    let blob = ethers.utils.hexConcat(elements);
    await sc.put(key1, blob);

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

  it("decode-inclusive-8k-blob-test", async function () {
    sc = await deployCloneImpl(
        factory,
        sc.address,
        [
          0, // storageCost
          0, // dcfFactor
          0, // startTime
          1 << 13,
          13, // maxKvSizeBits
          14, // shardSizeBits
          14 - 13, //_config.shardSizeBits - _config.maxKvSizeBits,
          13 - 5, // _config.maxKvSizeBits - sampleSizeBits
          1, // randomChecks
          40, // cutoff
          1024, // diffAdjDivisor
          0, // treasuryShare
        ],
        1, // minimumDiff
        1, // nonceLimit
        0, // prepaidAmount
        "0x0000000000000000000000000000000000000000", // treasury
        ownerAddr
    );
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let elements = new Array(256);

    for (let i = 0; i < 256; i++) {
      elements[i] = ethers.utils.formatBytes32String(i.toString());
    }

    let blob = ethers.utils.hexConcat(elements);
    await sc.put(key1, blob);
    await sc.put(key2, blob);

    const miner = "0xabcd000000000000000000000000000000000000";
    // 0x663bb8e714f953af09f3b9e17bf792824da0834fcfc4a9ff56e6d3d9a4a1e5ce
    const encodingKey1 = await sc.getEncodingKey(0, miner);
    const abiCoder = new ethers.utils.AbiCoder();
    const root = await ml.merkleRootMinTree(blob, 32);
    let rootArray = ethers.utils.arrayify(root);
    // convert bytes32 to bytes 24
    for (let i = 24; i < 32; i++) {
      rootArray[i] = 0;
    }
    const encodingKey = ethers.utils.keccak256(
      abiCoder.encode(["bytes32", "address", "uint256"], [ethers.utils.hexlify(rootArray), miner, 0])
    );
    expect(encodingKey1).to.equal(encodingKey);

    const sampleIdxInKv = 84;
    // note that mask is generated using 128KB blob size
    const mask = "0x1a3526f58594d237ca2cddc84670a3ebb004e745a57b22acbbaf335d2c13fcd2";
    const decodeProof = [
      [
        "0x0832889498a8fe4eef8b0892fa1249ebd7a8aed09d372faaed1c94dff01d7cc9",
        "0x17bcad2369edb3a5f36cd75ce8ff15260528af8bbb744e79e8d2a28acb7b6153",
      ],
      [
        [
          "0x1589c78081a735b082a0660ce1ec524c02a7e5b157893ce27698e7eddf56f98a",
          "0x20681d15437ae4f65a809d7ea04fdbe2584cab2cb20380652863fbaa4d9a677d",
        ],
        [
          "0x28d8955c5fd1041d9242171171f981fde7353dca48c613086af3adfadac3782e",
          "0x1e3e72972cb918190ac612852b3b50e264502907640a9519a8aedf3297154cf6",
        ],
      ],
      [
        "0x06803c666e791e3e2031c99a5eb8153f46e9a9b6b73ad5618bc9b59613d1b430",
        "0x1f1a2e683ab254d22156e964448b53742c4baf04e009ad532728391135f97716",
      ],
    ];
    expect(await sc.decodeSample(decodeProof, encodingKey, sampleIdxInKv, mask)).to.equal(true);

    // evaluate merkle proof
    let merkleProof = await ml.getProof(blob, 32, 8, sampleIdxInKv);
    let blobArray = ethers.utils.arrayify(blob);
    let decodedSample = ethers.BigNumber.from(blobArray.slice(sampleIdxInKv * 32, (sampleIdxInKv + 1) * 32));
    expect(await ml.verify(decodedSample, sampleIdxInKv, root, merkleProof)).to.equal(true);

    // combine all proof into single decode-and-inclusive proof
    const decodeProofData = abiCoder.encode(
        ["tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))"],
        [decodeProof]
    );
    const inclusiveProofData = abiCoder.encode(
      ["tuple(bytes32, bytes32, bytes32[])"],
      [[decodedSample, root, merkleProof]]
    );

    let encodedSample = ethers.BigNumber.from(mask).xor(decodedSample);

    expect(
      await sc.decodeAndCheckInclusive(
        0, // kvIdx
        sampleIdxInKv,
        miner,
        encodedSample,
        mask,
        inclusiveProofData,
        decodeProofData
      )
    ).to.equal(true);

    expect(
      await sc.decodeAndCheckInclusive(
        0, // kvIdx
        sampleIdxInKv + 1,
        miner,
        encodedSample,
        mask,
        inclusiveProofData,
        decodeProofData
      )
    ).to.equal(false);

    let initHash = "0x0000000000000000000000000000000000000000000000000000000000000054";

    expect(
      await sc.verifySamples(
        0, // shardIdx
        initHash, // hash0
        miner,
        [encodedSample],
        [mask],
        [inclusiveProofData],
        [decodeProofData]
      )
    ).to.equal(ethers.utils.keccak256(ethers.utils.hexConcat([initHash, encodedSample])));
  });

  it("verify-sample-8k-blob-2-samples-test", async function () {
    sc = await deployCloneImpl(
        factory,
        sc.address,
        [
          0, // storageCost
          0, // dcfFactor
          0, // startTime
          1 << 13, // 1 << _config.maxKvSizeBits
          13, // maxKvSizeBits
          14, // shardSizeBits
          14 - 13, //_config.shardSizeBits - _config.maxKvSizeBits,
          13 - 5, // _config.maxKvSizeBits - sampleSizeBits
          2, // randomChecks
          40, // cutoff
          1024, // diffAdjDivisor
          0, // treasuryShare
        ],
        1, // minimumDiff
        1, // nonceLimit
        0, // prepaidAmount
        "0x0000000000000000000000000000000000000000", // treasury
        ownerAddr
    );
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let testState = new TestState(sc, ml);
    let blob = testState.createBlob(0, 0, 256);
    let blob1 = testState.createBlob(1, 0, 256);
    await sc.put(key1, blob);
    await sc.put(key2, blob1);

    const miner = "0xabcd000000000000000000000000000000000000";
    const ecodingKeyFromSC = await testState.getEncodingKey(0, miner, true, sc, null);
    const ecodingKeyFromLocal = await testState.getEncodingKey(0, miner, false, null, ml);
    expect(ecodingKeyFromSC).to.equal(ecodingKeyFromLocal);

    // ==== decodeSample check ====
    const kvIdx = 0;
    const sampleIdxInKv = 84;
    // note that mask is generated using 128KB blob size
    const mask = "0x1a3526f58594d237ca2cddc84670a3ebb004e745a57b22acbbaf335d2c13fcd2";
    const decodeProof = [
      [
        "0x0832889498a8fe4eef8b0892fa1249ebd7a8aed09d372faaed1c94dff01d7cc9",
        "0x17bcad2369edb3a5f36cd75ce8ff15260528af8bbb744e79e8d2a28acb7b6153",
      ],
      [
        [
          "0x1589c78081a735b082a0660ce1ec524c02a7e5b157893ce27698e7eddf56f98a",
          "0x20681d15437ae4f65a809d7ea04fdbe2584cab2cb20380652863fbaa4d9a677d",
        ],
        [
          "0x28d8955c5fd1041d9242171171f981fde7353dca48c613086af3adfadac3782e",
          "0x1e3e72972cb918190ac612852b3b50e264502907640a9519a8aedf3297154cf6",
        ],
      ],
      [
        "0x06803c666e791e3e2031c99a5eb8153f46e9a9b6b73ad5618bc9b59613d1b430",
        "0x1f1a2e683ab254d22156e964448b53742c4baf04e009ad532728391135f97716",
      ],
    ];
    expect(await sc.decodeSample(decodeProof, ecodingKeyFromSC, sampleIdxInKv, mask)).to.equal(true);

    let blobArray = ethers.utils.arrayify(blob);
    let decodedSample = ethers.BigNumber.from(blobArray.slice(sampleIdxInKv * 32, (sampleIdxInKv + 1) * 32));
    let encodedSample = ethers.BigNumber.from(mask).xor(decodedSample);

    // =================================== The Second Samples =================================
    let hash0 = "0x0000000000000000000000000000000000000000000000000000000000000054";
    let nextHash0 = await sc.getNextHash0(hash0, encodedSample);
    let nextMask = "0x2b089b15a828c57b3eb07108a7a36488f3430d1b478b499253d06e3367378342";

    let [nextKvIdx, nextSampleIdxInKv, nextDecodedSample, nextEncodedSample] =
      await testState.getSampleIdxByHashWithMask(0, nextHash0, nextMask);
    await testState.getMerkleProof(nextKvIdx, nextSampleIdxInKv, nextDecodedSample);
    // calculate encoding key
    const nextEncodingKey = await sc.getEncodingKey(nextKvIdx, miner);
    const nextDecodeProof = [
      [
        "0x21eaa5a171f25bf2643a93700c04cf21da572e5b946fb9ca6ca3cf7a41256db2",
        "0x269cddd043e10fd0733bbeb2df6594a9e28008065e1f1b752b38b8621b265a30",
      ],
      [
        [
          "0x22fcb16796bb4d4c84507269a83c6ee3b78ecfb5329fe09a4a0609f4f2afdfb1",
          "0x14a94f013f6afe0af55e7ecad5ed05c28e56a3e9409755329f93895126567406",
        ],
        [
          "0x199c15935f667824d3c8636a3b8173a52b7c932fcc3539c369be1d6b5c601b0a",
          "0x0f3cac0df863f017443f1b20214d7ec0d900b5cdfa72e394aa175b08c7c849d8",
        ],
      ],
      [
        "0x198895d717cabc4065e3b957a854fe880872378605c4ac4f30b10bca1cc2c833",
        "0x2cc767691f3559288663f70488d5c610886d0aa8d7e497eb4277f5e0a055c0b5",
      ],
    ];

    let proof = await testState.getIntegrityProof(
      decodeProof,
      mask,
      ecodingKeyFromSC,
      kvIdx,
      sampleIdxInKv,
      decodedSample
    );
    let nextProof = await testState.getIntegrityProof(
      nextDecodeProof,
      nextMask,
      nextEncodingKey,
      nextKvIdx,
      nextSampleIdxInKv,
      nextDecodedSample
    );

    // ================== verify samples ==================
    expect(
      await sc.decodeAndCheckInclusive(
        0, // kvIdx
        sampleIdxInKv,
        miner,
        encodedSample,
        mask,
        proof.inclusiveProof,
        proof.decodeProof
      )
    ).to.equal(true);

    // combine all proof into single decode-and-inclusive proof

    expect(
      await sc.decodeAndCheckInclusive(
        nextKvIdx, // kvIdx
        nextSampleIdxInKv,
        miner,
        nextEncodedSample,
        nextMask,
        nextProof.inclusiveProof,
        nextProof.decodeProof
      )
    ).to.equal(true);

    expect(
      await sc.verifySamples(
        0, // shardIdx
        hash0, // hash0
        miner,
        [encodedSample, nextEncodedSample],
        [mask, nextMask],
        [proof.inclusiveProof, nextProof.inclusiveProof],
        [proof.decodeProof, nextProof.decodeProof]
      )
    ).to.equal(ethers.utils.keccak256(ethers.utils.hexConcat([nextHash0, nextEncodedSample])));

    await sc.mineWithFixedHash0(
        hash0,
        0,
        miner,
        0,
        [encodedSample, nextEncodedSample],
        [mask, nextMask],
        [proof.inclusiveProof, nextProof.inclusiveProof],
        [proof.decodeProof, nextProof.decodeProof]
    );
  });

  it("complete-mining-process", async function () {
    if (process.env.G16_WASM_PATH == null || process.env.G16_ZKEY_PATH == null) {
      console.log(
        "[Warning] complete-mining-process not running because of the lack of G16_WASM_PATH or G16_ZKEY_PATH"
      );
      return;
    } else {
      console.log("[Info] complete-mining-process running");
    }

    sc = await deployCloneImpl(
        factory,
        sc.address,
        [
          0, // storageCost
          0, // dcfFactor
          0, // startTime
          1 << 13, // 1 << _config.maxKvSizeBits
          13, // maxKvSizeBits
          14, // shardSizeBits
          14 - 13, //_config.shardSizeBits - _config.maxKvSizeBits,
          13 - 5, // _config.maxKvSizeBits - sampleSizeBits
          2, // randomChecks
          40, // cutoff
          1024, // diffAdjDivisor
          0, // treasuryShare
        ],
        1, // minimumDiff
        1, // nonceLimit
        0, // prepaidAmount
        "0x0000000000000000000000000000000000000000", // treasury
        ownerAddr
    );
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let testState = new TestState(sc, ml);

    let blob = testState.createRandomBlob(0, 256);
    let blob1 = testState.createRandomBlob(1, 256);
    sc.put(key1, blob);
    sc.put(key2, blob1);

    // the lastest block number is 11 at current state
    let bn = await ethers.provider.getBlockNumber();
    printlog("Mining at block height %d", bn);

    const blockNumber = ethers.utils.hexValue(bn);
    const block = await ethers.provider.send('eth_getBlockByNumber', [blockNumber, false]);
    const randao = block.mixHash;

    const miner = "0xabcd000000000000000000000000000000000000";
    let initHash0 = await testState.getInitHash0(randao, miner, 0);
    printlog("calculate the initHash0 %v", initHash0);

    let finalHash0 = await testState.execAllSamples(2, randao, miner, 0, 0);
    let proofs = await testState.getAllIntegrityProofs();
    let inclusiveProofs = [];
    let decodeProof = [];
    for(let proof of proofs) {
      inclusiveProofs.push(proof.inclusiveProof);
      decodeProof.push(proof.decodeProof);
    }
    let masks = testState.getMaskList();

    expect(
      await sc.verifySamples(
        0, // shardIdx
        initHash0, // hash0
        miner,
        testState.getEncodedSampleList(),
        masks,
        inclusiveProofs,
        decodeProof
      )
    ).to.equal(finalHash0);

    const encodedHeader = await generateRandaoProof(block);
    const hash = keccak256(encodedHeader);
    expect(hash).to.equal(block.hash);

    await sc.mine(
      bn,
      0,
      miner,
      0,
      testState.getEncodedSampleList(),
      masks,
      encodedHeader,
      inclusiveProofs,
      decodeProof
    );
  });
});
