const { web3 } = require("hardhat");
const { expect } = require("chai");
const { ethers } = require("hardhat");

/* declare const key */
const key1 = "0x0000000000000000000000000000000000000000000000000000000000000001";
const key2 = "0x0000000000000000000000000000000000000000000000000000000000000002";
const key3 = "0x0000000000000000000000000000000000000000000000000000000000000003";

describe("EthStorageContract Test", function () {
  it("decode-8k-blob-test", async function () {
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
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let elements = new Array(256);

    for (let i = 0; i < 256; i++) {
      elements[i] = ethers.utils.formatBytes32String(i.toString());
    }

    let blob = ethers.utils.hexConcat(elements);
    sc.put(key1, blob);

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
    const proof = abiCoder.encode(
      [
        "tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))",
        "uint256",
        "tuple(bytes32, bytes32, bytes32[])",
      ],
      [decodeProof, mask, [decodedSample, root, merkleProof]]
    );

    let encodedSample = ethers.BigNumber.from(mask).xor(decodedSample);

    expect(
      await sc.decodeAndCheckInclusive(
        0, // kvIdx
        sampleIdxInKv,
        miner,
        encodedSample,
        proof
      )
    ).to.equal(true);

    expect(
      await sc.decodeAndCheckInclusive(
        0, // kvIdx
        sampleIdxInKv + 1,
        miner,
        encodedSample,
        proof
      )
    ).to.equal(false);

    let initHash = "0x0000000000000000000000000000000000000000000000000000000000000054";

    expect(
      await sc.verifySamples(
        0, // shardIdx
        initHash, // hash0
        miner,
        [encodedSample],
        [proof]
      )
    ).to.equal(ethers.utils.keccak256(ethers.utils.hexConcat([initHash, encodedSample])));
  });

  it("verify-sample-8k-blob-2-samples-test", async function () {
    // TODO

    const EthStorageContract = await ethers.getContractFactory("TestEthStorageContract");
    const sc = await EthStorageContract.deploy(
      [
        13, // maxKvSizeBits
        14, // shardSizeBits
        2, // randomChecks
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
    const MerkleLib = await ethers.getContractFactory("TestMerkleLib");
    const ml = await MerkleLib.deploy();
    await ml.deployed();

    let elements = new Array(256);
    let elements1 = new Array(256);

    for (let i = 0; i < 256; i++) {
      elements[i] = ethers.utils.formatBytes32String(i.toString());
      elements1[i] = ethers.utils.formatBytes32String(i.toString());
    }

    let blob = ethers.utils.hexConcat(elements);
    let blob1 = ethers.utils.hexConcat(elements);
    sc.put(key1, blob);
    sc.put(key2, blob1);


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

    // ==== decodeSample check ==== 
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
    
    let blobArray = ethers.utils.arrayify(blob);
    let decodedSample = ethers.BigNumber.from(blobArray.slice(sampleIdxInKv * 32, (sampleIdxInKv + 1) * 32));
    let encodedSample = ethers.BigNumber.from(mask).xor(decodedSample);

    // evaluate merkle proof 
    let merkleProof = await ml.getProof(blob, 32, 8, sampleIdxInKv); 
    expect(await ml.verify(decodedSample, sampleIdxInKv, root, merkleProof)).to.equal(true);

    // =================================== The Second Samples =================================
    let hash0 = "0x1110000000000000000000000000000000000000000000000000000000000000";
    let nextHash0 = await sc.getNextHash0(hash0,encodedSample);

    let [nextSampleIdx,nextKvIdx,nextSampleIdxInKv] = await sc.getSampleIdx(0, nextHash0)
    // 46  0  46 
    console.log(nextSampleIdx,",",nextKvIdx,",",nextSampleIdxInKv)
    // nextSampleIdx = nextSampleIdx.toNumber() 
    nextSampleIdxInKv = nextSampleIdxInKv.toNumber()

    let blobArray1 = ethers.utils.arrayify(blob);
    let nextDecodedSample = ethers.BigNumber.from(blobArray.slice(nextSampleIdxInKv* 32, (nextSampleIdxInKv + 1) * 32));
    let nextEncodedSample = ethers.BigNumber.from(mask).xor(nextDecodedSample);

    let nextMerkleProof = await ml.getProof(blob, 32, 8, nextSampleIdxInKv); 
    expect(await ml.verify(nextDecodedSample, nextSampleIdxInKv, root, nextMerkleProof)).to.equal(true);

    // calculate encoding key 
    const nextEncodingKey = await sc.getEncodingKey(nextKvIdx, miner);
    console.log(nextEncodingKey) // 0xc032edf8d39a441b2be0f636d94c20774ea39194a6813efc10688437602f8873
    let nextMask = "0x29eb3987b926014ed5d96b83971f68ddf978f169e8aeb6725da729b9ca18d469"
    const nextDecodeProof = [
      [
        "0x20c2a11030ec40412150209b282d2df845f0b12c6c758d2e06605900faade319",
        "0x0d023df9f0dff4812e1b96c23d5085678faaac3d310c00878e269688f3ee3cf6",
      ],
      [
        [
          "0x0618ea43b52c7baa0dec5387fa0ce33bb5300e11697d1be9619e9ce70ab21581",
          "0x0e37c09eccbf7cd7a23de4e62de4d52b70ebfe140b980d456514d93c59471fb8",
        ],
        [
          "0x2dc3196a69b092ea51ee934247ee6c1f1317e756df2306f4853bc3aa80590f33",
          "0x0da0413edb2d0103fc80854e0184381d0960696efaf53e7392948b8eaecee557",
        ],
      ],
      [
        "0x2b25f8a08811cc7652418cbffa9e3782b0ad852f000c2cc6ea6d1c8cba770a4b",
        "0x2152f624f679989cc326eb3f827e6cc786e4869ba76ddcb6981fa0268a2d3ca7",
      ],
    ];
    expect(await sc.decodeSample(nextDecodeProof, nextEncodingKey, nextSampleIdxInKv, nextMask)).to.equal(true);

    
    // ================== verify samples ================== 

      // combine all proof into single decode-and-inclusive proof
      const proof = abiCoder.encode(
        [
          "tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))",
          "uint256",
          "tuple(bytes32, bytes32, bytes32[])",
        ],
        [decodeProof, mask, [decodedSample, root, merkleProof]]
      );
  
      expect(
        await sc.decodeAndCheckInclusive(
          0, // kvIdx
          sampleIdxInKv,
          miner,
          encodedSample,
          proof
        )
      ).to.equal(true);



      // combine all proof into single decode-and-inclusive proof
      const nextProof = abiCoder.encode(
        [
          "tuple(tuple(uint256, uint256), tuple(uint256[2], uint256[2]), tuple(uint256, uint256))",
          "uint256",
          "tuple(bytes32, bytes32, bytes32[])",
        ],
        [nextDecodeProof, nextMask, [nextDecodeProof, root, nextMerkleProof]]
      );
  
      expect(
        await sc.decodeAndCheckInclusive(
          nextKvIdx, // kvIdx
          nextSampleIdx,
          miner,
          nextEncodedSample,
          nextProof
        )
      ).to.equal(true);


    expect(
      await sc.verifySamples(
        0, // shardIdx
        hash0, // hash0
        miner,
        [encodedSample,nextEncodedSample],
        [proof,nextProof]
      )
    ).to.equal(ethers.utils.keccak256(ethers.utils.hexConcat([initHash, encodedSample])));
  });
});
