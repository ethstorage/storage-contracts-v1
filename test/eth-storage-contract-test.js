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
        "0x1282d54b7ca32fb9322b14d22b9ed8d8d74a2fa8199fc9b33f692175a0151dfa",
        "0x2ec90d197f18a88c179a7371d60523308e23239a418cc6f3140683d32f3038c6"
      ],
      [
        [
          "0x1ad0f63458899201b8e4b6ac99745f56a2e3fcb31059daa6316c9bbc1ff98796",
          "0x06d74f531689723f5bf1256e182cd6c39e5bf31343528cd9ba52e94fadb69c2a"
        ],
        [
          "0x2bda468dd57d4542b63c1039bebe6308533bd64976bd6820a776a505a601e7f0",
          "0x1e8b561f1b9aa9ccf3b9fc5178af00b4def50189b4241b24b1437540e71078fa"
        ]
      ],
      [
        "0x2f53719313a92f79ab72d1c9191186ffa20f553b8340070f5f6c120d9e07eefa",
        "0x2f89e19298611c499aa59fb59f3b0f4459378ca83b13facc2981fa396d202e1c"
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
        "0x08f2b57a05c4e7d93db6d445a8f41d13d3c7d07ec74b95a2aad5f6400eda803a",
        "0x1512576a70dc873c5d70d21b584e88f9f497390dc710a0416ef505e39d6954da"
      ],
      [
        [
          "0x1211829efb3afc4a217212703937cad70a4f21db1e6710afe61f7f9e4ea5ba22",
          "0x01a824f4a072f732a75aa03e89eb5ed299a0d18027ab30eda0961f02e37019b3"
        ],
        [
          "0x0a41eb1f5a366f1bbb948ffd77671da0e372b6b7b6cfb6e702e90e5d4370cbf2",
          "0x1e3588c5a06df2a1bcfa1cf57e12d46b5cfa0e21e634b897656fcbae6d08225b"
        ]
      ],
      [
        "0x05cad4a375ea33e595a342771c9eb46503dac95de18e38beef5f3186fbdd2a2f",
        "0x281d9c7b0edc98c9377ce751601d4fd6a2c925b0912d53436fd3eb84f0a67205"
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
        "0x08f2b57a05c4e7d93db6d445a8f41d13d3c7d07ec74b95a2aad5f6400eda803a",
        "0x1512576a70dc873c5d70d21b584e88f9f497390dc710a0416ef505e39d6954da"
      ],
      [
        [
          "0x1211829efb3afc4a217212703937cad70a4f21db1e6710afe61f7f9e4ea5ba22",
          "0x01a824f4a072f732a75aa03e89eb5ed299a0d18027ab30eda0961f02e37019b3"
        ],
        [
          "0x0a41eb1f5a366f1bbb948ffd77671da0e372b6b7b6cfb6e702e90e5d4370cbf2",
          "0x1e3588c5a06df2a1bcfa1cf57e12d46b5cfa0e21e634b897656fcbae6d08225b"
        ]
      ],
      [
        "0x05cad4a375ea33e595a342771c9eb46503dac95de18e38beef5f3186fbdd2a2f",
        "0x281d9c7b0edc98c9377ce751601d4fd6a2c925b0912d53436fd3eb84f0a67205"
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
        "0x2505556e329c539570d437dee5e76b753d94c98988bdbd8466131c993bf0e459",
        "0x19a70541e1fb2436fbb2e9f7b444515f8b7831dbe1731b1d34a2aeec92d1fba9"
      ],
      [
        [
          "0x20ea125a8fbadc14fa99bb19497b065383d814bb7452227bdeae152c60145267",
          "0x293b93976a31d8f79d1896b12dbc377fc05b15aac014a79009ea0e39378ede8c"
        ],
        [
          "0x2b86da20245342b62e5e0b837c814cb11962b8a7c7489747c953c0f629602826",
          "0x1e26c4ca8d1f77d3bda5ff318fc315158ebea7701e9be700063b1a859390a06e"
        ]
      ],
      [
        "0x11e399c647363330c3327223bd188712eb4bc84b7f00d0ae48decb8cc26822fd",
        "0x2b37fb4fbe73864fbb824c06e920b11bcc2a91e5bc9e93ca01b2899426882e6f"
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
