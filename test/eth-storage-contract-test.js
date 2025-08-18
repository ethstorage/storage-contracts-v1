const { expect } = require("chai");
require("dotenv").config();

const { TestState } = require("./lib/test-helper");
const { printlog } = require("./lib/print");
const { generateRandaoProof } = require("./lib/prover");
const { ethers, upgrades } = require("hardhat");

/* declare const key */
const key1 = "0x0000000000000000000000000000000000000000000000000000000000000001";
const key2 = "0x0000000000000000000000000000000000000000000000000000000000000002";
const key3 = "0x0000000000000000000000000000000000000000000000000000000000000003";
const ownerAddr = "0x0000000000000000000000000000000000000001";

describe("EthStorageContract Test", function () {
  this.timeout(300000);

  it("decode-8k-blob-test", async function () {
    const sc = await upgrades.deployProxy(await ethers.getContractFactory("TestEthStorageContractM1"),
      [
        1, // minimumDiff
        0, // prepaidAmount
        1, // nonceLimit
        "0x0000000000000000000000000000000000000000", // treasury
        ownerAddr
      ], {
        constructorArgs: [
          [
            13, // maxKvSizeBits
            14, // shardSizeBits
            1, // randomChecks
            40, // cutoff
            1024, // diffAdjDivisor
            0, // treasuryShare
          ],
          0, // startTime
          0, // storageCost
          0, // dcfFactor
        ]
    }
    );

    await sc.waitForDeployment();

    let elements = new Array(256);

    for (let i = 0; i < 256; i++) {
      elements[i] = ethers.encodeBytes32String(i.toString());
    }

    let blob = ethers.concat(elements);
    await sc.put(key1, blob);

    const encodingKey = "0x1122000000000000000000000000000000000000000000000000000000000000";
    const sampleIdxInKv = 123;
    const mask = "0x301b9cec8aae1155d883c48308dbd2f24e54aff21bfbd7b3d1afecb5507bf521";
    const proof = [
      [
        "0x78e4c42fa4f0d326f6ed23e08ccf4a1690d020b5307476339761c878e4fd93b",
        "0x2f8d5730408615ffd0d78c104faeed0dfc9556bd5cc858ff00d16d5c5ee4bec5"
      ],
      [
        [
          "0x3707dc3b24f4cd77289dc3fd93ac2ba12098f1e93a6c370c70de94051661ceb",
          "0x16130e5f937a11f65450d3006ebc6d15174f35277ee95989cc73ed661fb84278"
        ],
        [
          "0x150f361f8b43acf2f6b2ecabfd0e300e95da35949c5cf80fc811dec7aab968ae",
          "0xa8d2fb3261418d4ff2ab9dd13e29a79cb3a821aaa30534f7a9a015699c5f274"
        ]
      ],
      [
        "0x2a4c45f2e1232c2ef8130a52678a22012131f39b4cfdfd1f47daa0a89f14e0c",
        "0x80b1f60362a990582d231ceac6f8af57feec7d0d342789657cf4377f7c14cd4"
      ]
    ];
    const abiCoder = new ethers.AbiCoder();
    const decodeProofBytes = abiCoder.encode(
      ["tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))"],
      [proof]
    );
    expect(await sc.decodeSampleCheck(decodeProofBytes, encodingKey, sampleIdxInKv, mask)).to.equal(true);
  });

  it("decode-inclusive-8k-blob-test", async function () {

    const sc = await upgrades.deployProxy(await ethers.getContractFactory("TestEthStorageContractM1"),
      [
        1, // minimumDiff
        0, // prepaidAmount
        1, // nonceLimit
        "0x0000000000000000000000000000000000000000", // treasury
        ownerAddr
      ], {
        constructorArgs: [
          [
            13, // maxKvSizeBits
            14, // shardSizeBits
            1, // randomChecks
            40, // cutoff
            1024, // diffAdjDivisor
            0, // treasuryShare
          ],
          0, // startTime
          0, // storageCost
          0, // dcfFactor
        ]
    }
    );

    await sc.waitForDeployment();

    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.waitForDeployment();

    let elements = new Array(256);

    for (let i = 0; i < 256; i++) {
      elements[i] = ethers.encodeBytes32String(i.toString());
    }

    let blob = ethers.concat(elements);
    await sc.put(key1, blob);
    await sc.put(key2, blob);

    const miner = "0xabcd000000000000000000000000000000000000";
    // 0x663bb8e714f953af09f3b9e17bf792824da0834fcfc4a9ff56e6d3d9a4a1e5ce
    const encodingKey1 = await sc.getEncodingKey(0, miner);
    const abiCoder = new ethers.AbiCoder();
    const root = await ml.merkleRootMinTree(blob, 32);
    let rootArray = ethers.getBytes(root);
    // convert bytes32 to bytes 24
    for (let i = 24; i < 32; i++) {
      rootArray[i] = 0;
    }
    const encodingKey = ethers.keccak256(
      abiCoder.encode(["bytes32", "address", "uint256"], [ethers.hexlify(rootArray), miner, 0])
    );
    expect(encodingKey1).to.equal(encodingKey);

    const sampleIdxInKv = 84;
    // note that mask is generated using 128KB blob size
    const mask = "0x1a3526f58594d237ca2cddc84670a3ebb004e745a57b22acbbaf335d2c13fcd2";
    const decodeProof = [
      [
        "0x2c033866f9339f6b7e486bd2683ad044c749d938282e182bcfcd361e89c3dcfe",
        "0x16b919204d3f44e46418e27ca133da6b803649b2f22ad8a7c3fb6a31e5fb1b30",
      ],
      [
        [
          "0x76267516ab7c70392c756aacfbcdbb9726afde5664b334f73b046eeb084b28b",
          "0x27f6cb07ef3ce13bd0c34221d33521517cb4b690f2b8e8360086008e86dbf75f",
        ],
        [
          "0x2a13ed27ea4e281f99e73690d3678059bffed60c052573b7c16d84f50dc8af37",
          "0x16c1ed06157a1c0e115a59134d9912d2cce885f772d369fdc755cef6a5e1e4f7",
        ],
      ],
      [
        "0x2ac75b5f6e0858b245b6e88362435a5b920904b2dec41e4bf372b1d50b171d24",
        "0x172cb102a51789ce37fc019d32af773166c4dfee8a5f0d6698735c477cc6ba77",
      ]
    ];
    // combine all proof into single decode-and-inclusive proof
    const decodeProofData = abiCoder.encode(
      ["tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))"],
      [decodeProof]
    );
    expect(await sc.decodeSampleCheck(decodeProofData, encodingKey, sampleIdxInKv, mask)).to.equal(true);

    // evaluate merkle proof
    let merkleProofImmutable = await ml.getProof(blob, 32, 8, sampleIdxInKv);
    let merkleProof = [...merkleProofImmutable];
    let blobArray = ethers.getBytes(blob);
    let sampleBytes = blobArray.slice(sampleIdxInKv * 32, (sampleIdxInKv + 1) * 32);
    let decodedSampleBig = ethers.toBigInt(ethers.hexlify(sampleBytes), 32);
    let decodedSample = ethers.toBeHex(decodedSampleBig);

    expect(await ml.verify(decodedSample, sampleIdxInKv, root, merkleProof)).to.equal(true);

    const inclusiveProofData = abiCoder.encode(
      ["tuple(bytes32, bytes32, bytes32[])"],
      [[decodedSample, root, merkleProof]]
    );

    let encodedSampleBig = ethers.toBigInt(mask, 32) ^ (decodedSampleBig);
    let encodedSample = ethers.toBeHex(encodedSampleBig);

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
    ).to.equal(ethers.keccak256(ethers.concat([initHash, encodedSample])));
  });

  it("verify-sample-8k-blob-2-samples-test", async function () {
    const sc = await upgrades.deployProxy(await ethers.getContractFactory("TestEthStorageContractM1"),
      [
        1, // minimumDiff
        0, // prepaidAmount
        1, // nonceLimit
        "0x0000000000000000000000000000000000000000", // treasury
        ownerAddr
      ], {
        constructorArgs: [
          [
            13, // maxKvSizeBits
            14, // shardSizeBits
            2, // randomChecks
            40, // cutoff
            1024, // diffAdjDivisor
            0, // treasuryShare
          ],
          0, // startTime
          0, // storageCost
          0, // dcfFactor
        ]
    }
    );

    await sc.waitForDeployment();

    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.waitForDeployment();
    const mlAddr = await ml.getAddress()

    let testState = new TestState(sc, ml);
    let blob = testState.createBlob(0, 0, 256);
    let blob1 = testState.createBlob(1, 0, 256);
    await sc.put(key1, blob);
    await sc.put(key2, blob1);

    const miner = "0xabcd000000000000000000000000000000000000";
    const ecodingKeyFromSC = await testState.getEncodingKey(0, miner, true);
    const ecodingKeyFromLocal = await testState.getEncodingKey(0, miner, false);
    expect(ecodingKeyFromSC).to.equal(ecodingKeyFromLocal);

    // ==== decodeSample check ====
    const kvIdx = 0;
    const sampleIdxInKv = 84;
    // note that mask is generated using 128KB blob size
    const mask = "0x1a3526f58594d237ca2cddc84670a3ebb004e745a57b22acbbaf335d2c13fcd2";
    const decodeProof = [
      [
        "0x2c033866f9339f6b7e486bd2683ad044c749d938282e182bcfcd361e89c3dcfe",
        "0x16b919204d3f44e46418e27ca133da6b803649b2f22ad8a7c3fb6a31e5fb1b30"
      ],
      [
        [
          "0x76267516ab7c70392c756aacfbcdbb9726afde5664b334f73b046eeb084b28b",
          "0x27f6cb07ef3ce13bd0c34221d33521517cb4b690f2b8e8360086008e86dbf75f"
        ],
        [
          "0x2a13ed27ea4e281f99e73690d3678059bffed60c052573b7c16d84f50dc8af37",
          "0x16c1ed06157a1c0e115a59134d9912d2cce885f772d369fdc755cef6a5e1e4f7"
        ]
      ],
      [
        "0x2ac75b5f6e0858b245b6e88362435a5b920904b2dec41e4bf372b1d50b171d24",
        "0x172cb102a51789ce37fc019d32af773166c4dfee8a5f0d6698735c477cc6ba77"
      ]
    ];
    const abiCoder = new ethers.AbiCoder();
    const decodeProofBytes = abiCoder.encode(
      ["tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))"],
      [decodeProof]
    );
    expect(await sc.decodeSampleCheck(decodeProofBytes, ecodingKeyFromSC, sampleIdxInKv, mask)).to.equal(true);

    let blobArray = ethers.getBytes(blob);

    let sampleBytes = blobArray.slice(sampleIdxInKv * 32, (sampleIdxInKv + 1) * 32);
    let decodedSampleBig = ethers.toBigInt(ethers.hexlify(sampleBytes));
    let decodedSample = ethers.toBeHex(decodedSampleBig);

    let encodedSampleBig = ethers.toBigInt(mask) ^ decodedSampleBig;
    let encodedSample = ethers.toBeHex(encodedSampleBig, 32);

    // =================================== The Second Samples =================================
    let hash0 = "0x0000000000000000000000000000000000000000000000000000000000000054";
    let nextHash0 = await sc.getNextHash0(hash0, encodedSample);
    let nextMask = "0x2b089b15a828c57b3eb07108a7a36488f3430d1b478b499253d06e3367378342";

    let [nextKvIdx, nextSampleIdxInKv, nextDecodedSampleBig, nextEncodedSampleBig] =
      await testState.getSampleIdxByHashWithMask(0, nextHash0, nextMask);
    await testState.getMerkleProof(nextKvIdx, nextSampleIdxInKv, nextDecodedSampleBig);
    let nextDecodedSample = ethers.toBeHex(nextDecodedSampleBig, 32);
    let nextEncodedSample = ethers.toBeHex(nextEncodedSampleBig, 32);
    // calculate encoding key
    const nextEncodingKey = await sc.getEncodingKey(nextKvIdx, miner);
    const nextDecodeProof = [
      [
        "0x2ef7a57d70371f477e072a9407178d7b4c42ca8215843ce12f46010e311b0004",
        "0x1393325cf0b0e9e46207558c8dd0d273075de56ac78da03217cbbd72aa592609"
      ],
      [
        [
          "0xca2d640d1612fea57318495313a0f0d77b83e5e62a1ec97dcf4805a745ae1a9",
          "0x25ae9533cde5b51a30d186ffff4a59522e93ec7521447c1f688492e1fa4b3fe9"
        ],
        [
          "0xd2e67ee952009fb593d48320969bf8b22b37ad0fe15310d902171c6acc9c38e",
          "0xcc0ec025ad9b8220ec9ffb62a6777e6ed801fbe45d6ec5592327cd3d72806b2"
        ]
      ],
      [
        "0xdb81bb258c62ce5aa5170a1ea35aea4dbddb2833a6a991e6192d5b708083be7",
        "0xc18b0fc292568fb207f0c2c4694c52127bc55762c8bf96d4d01c96455ade62f"
      ]
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
    ).to.equal(ethers.keccak256(ethers.concat([nextHash0, nextEncodedSample])));

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

    const sc = await upgrades.deployProxy(await ethers.getContractFactory("TestEthStorageContractM1"),
      [
        1, // minimumDiff
        0, // prepaidAmount
        1, // nonceLimit
        "0x0000000000000000000000000000000000000000", // treasury
        ownerAddr
      ], {
        constructorArgs: [
          [
            13, // maxKvSizeBits
            14, // shardSizeBits
            2, // randomChecks
            40, // cutoff
            1024, // diffAdjDivisor
            0, // treasuryShare
          ],
          0, // startTime
          0, // storageCost
          0, // dcfFactor
        ]
    }
    );

    await sc.waitForDeployment();

    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.waitForDeployment();

    let testState = new TestState(sc, ml);

    let blob = testState.createRandomBlob(0, 256);
    let blob1 = testState.createRandomBlob(1, 256);
    sc.put(key1, blob);
    sc.put(key2, blob1);

    // the lastest block number is 11 at current state
    let bn = await ethers.provider.getBlockNumber();
    console.log("Mining at block height %d", bn);

    const blockNumber = ethers.toBeHex(bn);
    const block = await ethers.provider.send('eth_getBlockByNumber', [blockNumber, false]);
    const randao = block.mixHash;

    const miner = "0xabcd000000000000000000000000000000000000";
    let initHash0 = await testState.getInitHash0(randao, miner, 0);
    printlog("calculate the initHash0 %v", initHash0);

    let finalHash0 = await testState.execAllSamples(2, randao, miner, 0, 0);
    let proofs = await testState.getAllIntegrityProofs();
    let inclusiveProofs = [];
    let decodeProof = [];
    for (let proof of proofs) {
      inclusiveProofs.push(proof.inclusiveProof);
      decodeProof.push(proof.decodeProof);
    }
    const masks = testState.getMaskList();
    const masksHex = masks.map((mask) => ethers.toBeHex(ethers.toBigInt(mask), 32));
    const encoded = testState.getEncodedSampleList();
    const encodedHex = encoded.map((sample) => ethers.toBeHex(ethers.toBigInt(sample), 32));

    expect(
      await sc.verifySamples(
        0, // shardIdx
        initHash0, // hash0
        miner,
        encodedHex,
        masksHex,
        inclusiveProofs,
        decodeProof
      )
    ).to.equal(finalHash0);

    const encodedHeader = await generateRandaoProof(block);
    const hash = ethers.keccak256(encodedHeader);
    expect(hash).to.equal(block.hash);

    await sc.mine(
      bn,
      0,
      miner,
      0,
      encodedHex,
      masksHex,
      encodedHeader,
      inclusiveProofs,
      decodeProof
    );
  });
});
