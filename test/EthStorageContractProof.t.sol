// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/Test.sol";
import {StorageContract} from "../contracts/StorageContract.sol";
import {MerkleLib} from "../contracts/libraries/MerkleLib.sol";
import {RandaoProver} from "./lib/RandaoProver.sol";
import {ChainDataHelper} from "./lib/ChainDataHelper.sol";
import {TestEthStorageContractM1} from "./mocks/TestEthStorageContractM1.sol";

contract EthStorageContractProofTest is ChainDataHelper {
    using stdJson for string;

    struct Groth16Proof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
    }

    address internal constant MINER = address(0xABcD000000000000000000000000000000000000);
    address internal constant OWNER = address(0x1);
    bytes32 internal constant KEY1 = bytes32(uint256(0x1));
    bytes32 internal constant KEY2 = bytes32(uint256(0x2));

    mapping(uint256 => bytes) internal kvBlobs;

    function testDecode8kBlob() public {
        TestEthStorageContractM1 sc = _deployM1(1);

        bytes memory blob = _buildSequentialBlob(0, 256);
        kvBlobs[0] = blob;
        sc.put(KEY1, blob);

        uint256 sampleIdxInKv = 123;
        uint256 encodingKey = 0x1122000000000000000000000000000000000000000000000000000000000000;
        uint256 mask = 0x301b9cec8aae1155d883c48308dbd2f24e54aff21bfbd7b3d1afecb5507bf521;

        Groth16Proof memory proof = _decodeProofSample123();
        bytes memory proofBytes = _encodeProof(proof);

        bool ok = sc.decodeSampleCheck(proofBytes, encodingKey, sampleIdxInKv, mask);
        assertTrue(ok);
    }

    function testDecodeInclusive8kBlob() public {
        TestEthStorageContractM1 sc = _deployM1(1);

        bytes memory blob = _buildSequentialBlob(0, 256);
        kvBlobs[0] = blob;
        sc.put(KEY1, blob);
        sc.put(KEY2, blob);

        bytes32 onChainKey = sc.getEncodingKey(0, MINER);
        bytes32 localKey = _computeEncodingKey(blob, MINER, 0);
        assertEq(onChainKey, localKey);

        uint256 sampleIdxInKv = 84;
        uint256 mask = 0x1a3526f58594d237ca2cddc84670a3ebb004e745a57b22acbbaf335d2c13fcd2;

        Groth16Proof memory proof = _decodeProofSample84();
        bytes memory decodeProofData = _encodeProof(proof);
        assertTrue(sc.decodeSampleCheck(decodeProofData, uint256(onChainKey), sampleIdxInKv, mask));

        bytes32 root = MerkleLib.merkleRootWithMinTree(blob, 32);
        bytes32[] memory merkleProof = MerkleLib.getProof(blob, 32, 8, sampleIdxInKv);
        bytes32 decodedSample = _loadChunk(blob, sampleIdxInKv);
        bytes32 encodedSample = bytes32(uint256(decodedSample) ^ mask);

        assertTrue(MerkleLib.verify(keccak256(abi.encode(decodedSample)), sampleIdxInKv, root, merkleProof));

        bytes memory inclusiveProof = _encodeInclusiveProof(decodedSample, root, merkleProof);
        assertTrue(
            sc.decodeAndCheckInclusive(0, sampleIdxInKv, MINER, encodedSample, mask, inclusiveProof, decodeProofData)
        );
        assertFalse(
            sc.decodeAndCheckInclusive(
                0, sampleIdxInKv + 1, MINER, encodedSample, mask, inclusiveProof, decodeProofData
            )
        );

        bytes32 initHash = bytes32(uint256(0x54));
        bytes32[] memory encodedSamples = new bytes32[](1);
        encodedSamples[0] = encodedSample;
        uint256[] memory masks = new uint256[](1);
        masks[0] = mask;
        bytes[] memory inclusiveProofs = new bytes[](1);
        inclusiveProofs[0] = inclusiveProof;
        bytes[] memory decodeProofs = new bytes[](1);
        decodeProofs[0] = decodeProofData;

        bytes32 expected = keccak256(abi.encode(initHash, encodedSample));
        assertEq(sc.verifySamples(0, initHash, MINER, encodedSamples, masks, inclusiveProofs, decodeProofs), expected);
    }

    function testVerify2Samples() public {
        TestEthStorageContractM1 sc = _deployM1(2);

        bytes memory blob0 = _buildSequentialBlob(0, 256);
        bytes memory blob1 = _buildSequentialBlob(0, 256);
        kvBlobs[0] = blob0;
        kvBlobs[1] = blob1;
        sc.put(KEY1, blob0);
        sc.put(KEY2, blob1);

        bytes32 onChainKey = sc.getEncodingKey(0, MINER);
        bytes32 localKey = _computeEncodingKey(blob0, MINER, 0);
        assertEq(onChainKey, localKey);

        // The first sample
        uint256 sampleIdx0 = 84;
        uint256 mask0 = 0x1a3526f58594d237ca2cddc84670a3ebb004e745a57b22acbbaf335d2c13fcd2;
        bytes32 decodedSample0 = _loadChunk(blob0, sampleIdx0);
        bytes32 encodedSample0 = bytes32(uint256(decodedSample0) ^ mask0);

        Groth16Proof memory proof0 = _decodeProofSample84();
        bytes memory decodeProof0 = _encodeProof(proof0);
        assertTrue(sc.decodeSampleCheck(decodeProof0, uint256(onChainKey), sampleIdx0, mask0));

        bytes32 root0 = MerkleLib.merkleRootWithMinTree(blob0, 32);
        bytes32[] memory merkleProof0 = MerkleLib.getProof(blob0, 32, 8, sampleIdx0);
        bytes memory inclusiveProof0 = _encodeInclusiveProof(decodedSample0, root0, merkleProof0);
        assertTrue(
            sc.decodeAndCheckInclusive(0, sampleIdx0, MINER, encodedSample0, mask0, inclusiveProof0, decodeProof0)
        );

        // The second sample
        bytes32 hash0 = bytes32(uint256(0x54));
        bytes32 nextHash0 = keccak256(abi.encode(hash0, encodedSample0));

        (, uint256 kvIdx1, uint256 sampleIdx1) = sc.getSampleIdx(0, nextHash0);

        bytes memory targetBlob = kvIdx1 == 0 ? blob0 : blob1;
        bytes32 decodedSample1 = _loadChunk(targetBlob, sampleIdx1);

        Groth16Proof memory proof1 = _decodeProofNext();
        bytes memory decodeProof1 = _encodeProof(proof1);
        bytes32 encodingKey1 = sc.getEncodingKey(kvIdx1, MINER);
        uint256 mask1 = 0x2b089b15a828c57b3eb07108a7a36488f3430d1b478b499253d06e3367378342;

        bytes32 encodedSample1 = bytes32(uint256(decodedSample1) ^ mask1);
        bytes32 root1 = MerkleLib.merkleRootWithMinTree(targetBlob, 32);
        bytes32[] memory merkleProof1 = MerkleLib.getProof(targetBlob, 32, 8, sampleIdx1);
        bytes memory inclusiveProof1 = _encodeInclusiveProof(decodedSample1, root1, merkleProof1);
        assertTrue(sc.decodeSampleCheck(decodeProof1, uint256(encodingKey1), sampleIdx1, mask1));

        assertTrue(
            sc.decodeAndCheckInclusive(kvIdx1, sampleIdx1, MINER, encodedSample1, mask1, inclusiveProof1, decodeProof1)
        );

        // Verify both samples together
        bytes32[] memory encodedSamples = new bytes32[](2);
        encodedSamples[0] = encodedSample0;
        encodedSamples[1] = encodedSample1;
        uint256[] memory masks = new uint256[](2);
        masks[0] = mask0;
        masks[1] = mask1;
        bytes[] memory inclusiveProofs = new bytes[](2);
        inclusiveProofs[0] = inclusiveProof0;
        inclusiveProofs[1] = inclusiveProof1;
        bytes[] memory decodeProofs = new bytes[](2);
        decodeProofs[0] = decodeProof0;
        decodeProofs[1] = decodeProof1;

        bytes32 expected = keccak256(abi.encode(nextHash0, encodedSample1));
        assertEq(sc.verifySamples(0, hash0, MINER, encodedSamples, masks, inclusiveProofs, decodeProofs), expected);

        // Partial mining process mocked
        sc.mineWithFixedHash0(hash0, 0, MINER, 0, encodedSamples, masks, inclusiveProofs, decodeProofs);
    }

    function testCompleteMiningProcess() public {
        if (bytes(vm.envString("RPC_URL_L1")).length == 0) {
            vm.skip(true, "Skipping testCompleteMiningProcess: RPC_URL_L1 not set");
            return;
        }
        string memory zkeyPathEnv = vm.envString("G16_ZKEY_PATH");
        string memory wasmPathEnv = vm.envString("G16_WASM_PATH");
        if (bytes(zkeyPathEnv).length == 0 || bytes(wasmPathEnv).length == 0) {
            vm.skip(true, "Skipping testCompleteMiningProcess: G16_ZKEY_PATH or G16_WASM_PATH is not set");
            return;
        }
        if (!_isSnarkjsInstalled()) {
            vm.skip(true, "Skipping testCompleteMiningProcess: snarkjs is not installed");
            return;
        }

        uint256 randomChecks = 2;
        TestEthStorageContractM1 sc = _deployM1(randomChecks);
        vm.deal(address(sc), 1 ether);
        vm.startPrank(OWNER);
        sc.setEnforceMinerRole(false);
        vm.stopPrank();

        bytes memory blob0 = _buildSequentialBlob(0, 256);
        bytes memory blob1 = _buildSequentialBlob(0, 256);
        kvBlobs[0] = blob0;
        kvBlobs[1] = blob1;
        sc.put(KEY1, blob0);
        sc.put(KEY2, blob1);

        (ChainDataHelper.BlockHeader memory header, bytes32 blockHash) = fetchLatestBlockHeader();
        sc.setMockBlockNumber(header.number);
        sc.setMockRandao(header.mixHash);

        uint256 nonce = 0;
        bytes32 initHash0 = keccak256(abi.encode(MINER, header.mixHash, nonce));

        bytes32[] memory encodedSamples = new bytes32[](randomChecks);
        uint256[] memory masks = new uint256[](randomChecks);
        bytes[] memory inclusiveProofs = new bytes[](randomChecks);
        bytes[] memory decodeProofs = new bytes[](randomChecks);

        bytes32 currentHash = initHash0;

        for (uint256 i = 0; i < randomChecks; i++) {
            (, uint256 kvIdx, uint256 sampleIdx) = sc.getSampleIdx(0, currentHash);
            bytes memory blob = kvBlobs[kvIdx];
            bytes32 decodedSample = _loadChunk(blob, sampleIdx);
            bytes32 encodingKey = _computeEncodingKey(blob, MINER, kvIdx);
            bytes32 encodedSample = _processSample(
                sc,
                kvIdx,
                sampleIdx,
                blob,
                decodedSample,
                encodingKey,
                i,
                encodedSamples,
                masks,
                inclusiveProofs,
                decodeProofs
            );

            currentHash = keccak256(abi.encode(currentHash, encodedSample));
        }

        bytes32 solutionHash =
            sc.verifySamples(0, initHash0, MINER, encodedSamples, masks, inclusiveProofs, decodeProofs);
        assertEq(solutionHash, currentHash);

        bytes memory randaoProof = RandaoProver.generateRandaoProof(header);
        assertEq(keccak256(randaoProof), blockHash);

        sc.mine(header.number, 0, MINER, nonce, encodedSamples, masks, randaoProof, inclusiveProofs, decodeProofs);
    }

    // -------------------------------------------------------------------------
    // Helpers

    function _deployM1(uint256 randomChecks) internal returns (TestEthStorageContractM1) {
        bytes memory initData =
            abi.encodeWithSelector(TestEthStorageContractM1.initialize.selector, 1, 0, 5000, address(0), OWNER);

        Options memory opts;
        opts.constructorData = abi.encode(StorageContract.Config(13, 14, randomChecks, 40, 1024, 0), 0, 0, 0);
        opts.unsafeSkipAllChecks = true;

        address proxy = Upgrades.deployTransparentProxy(
            "TestEthStorageContractM1.sol:TestEthStorageContractM1", OWNER, initData, opts
        );

        return TestEthStorageContractM1(payable(proxy));
    }

    function _processSample(
        TestEthStorageContractM1 sc,
        uint256 kvIdx,
        uint256 sampleIdx,
        bytes memory blob,
        bytes32 decodedSample,
        bytes32 encodingKey,
        uint256 index,
        bytes32[] memory encodedSamples,
        uint256[] memory masks,
        bytes[] memory inclusiveProofs,
        bytes[] memory decodeProofs
    ) internal returns (bytes32 encodedSample) {
        // Generate decode proof for the sample
        uint256 encodingKeyMod = uint256(encodingKey) % sc.getModBn254();
        string memory encodingKeyStr = vm.toString(encodingKeyMod);
        uint256 sampleIdxInKvRu = sc.getXIn(sampleIdx);
        string memory sampleIdxInKvRuStr = Strings.toHexString(sampleIdxInKvRu, 32);
        bytes memory witnessJson =
            abi.encodePacked('{"encodingKeyIn":"', encodingKeyStr, '","xIn":"', sampleIdxInKvRuStr, '"}');
        (Groth16Proof memory proof, uint256[3] memory signals) = _generateG16Proof(witnessJson);
        bytes memory decodeProof = _encodeProof(proof);

        // Verify the decode proof
        uint256 maskValue = signals[2];
        assertTrue(sc.decodeSampleCheck(decodeProof, uint256(encodingKey), sampleIdx, maskValue));

        // Generate inclusive proof for the sample
        bytes32 root = MerkleLib.merkleRootWithMinTree(blob, 32);
        bytes32[] memory merkleProof = MerkleLib.getProof(blob, 32, 8, sampleIdx);
        bytes memory inclusiveProof = _encodeInclusiveProof(decodedSample, root, merkleProof);

        // Verify the inclusive proof
        encodedSample = bytes32(uint256(decodedSample) ^ maskValue);
        assertTrue(
            sc.decodeAndCheckInclusive(kvIdx, sampleIdx, MINER, encodedSample, maskValue, inclusiveProof, decodeProof)
        );

        encodedSamples[index] = encodedSample;
        masks[index] = maskValue;
        inclusiveProofs[index] = inclusiveProof;
        decodeProofs[index] = decodeProof;
    }

    function _generateG16Proof(bytes memory witnessJson)
        internal
        returns (Groth16Proof memory proof, uint256[3] memory signals)
    {
        string memory wasmPath = vm.envString("G16_WASM_PATH");
        string memory zkeyPath = vm.envString("G16_ZKEY_PATH");
        require(bytes(wasmPath).length != 0 && bytes(zkeyPath).length != 0, "g16 env unset");

        string memory tmpDir = "tmp";
        vm.createDir(tmpDir, true);

        string memory witnessPath = string.concat(tmpDir, "/tmp_g16_witness.json");
        string memory wtnsPath = string.concat(tmpDir, "/tmp_g16_witness.wtns");
        string memory proofPath = string.concat(tmpDir, "/tmp_g16_proof.json");
        string memory publicPath = string.concat(tmpDir, "/tmp_g16_public.json");

        vm.writeFile(witnessPath, string(witnessJson));

        string[] memory witnessCmd = new string[](6);
        witnessCmd[0] = "snarkjs";
        witnessCmd[1] = "wc";
        witnessCmd[2] = wasmPath;
        witnessCmd[3] = witnessPath;
        witnessCmd[4] = wtnsPath;

        Vm.FfiResult memory witnessRes = vm.tryFfi(witnessCmd);
        require(witnessRes.exitCode == 0, string.concat("wtns calculate failed: ", string(witnessRes.stderr)));

        string[] memory proveCmd = new string[](7);
        proveCmd[0] = "snarkjs";
        proveCmd[1] = "g16p";
        proveCmd[2] = zkeyPath;
        proveCmd[3] = wtnsPath;
        proveCmd[4] = proofPath;
        proveCmd[5] = publicPath;

        Vm.FfiResult memory proveRes = vm.tryFfi(proveCmd);
        require(proveRes.exitCode == 0, string.concat("snarkjs prove failed: ", string(proveRes.stderr)));

        string memory proofJson = _readFileViaCat(proofPath);
        require(bytes(proofJson).length != 0, "empty proof json");
        string memory publicJsonRaw = _readFileViaCat(publicPath);
        require(bytes(publicJsonRaw).length != 0, "empty public json");
        string memory publicJson = string.concat('{"signals":', publicJsonRaw, "}");

        proof.a = [vm.parseUint(proofJson.readString(".pi_a[0]")), vm.parseUint(proofJson.readString(".pi_a[1]"))];
        proof.b = [
            [vm.parseUint(proofJson.readString(".pi_b[0][1]")), vm.parseUint(proofJson.readString(".pi_b[0][0]"))],
            [vm.parseUint(proofJson.readString(".pi_b[1][1]")), vm.parseUint(proofJson.readString(".pi_b[1][0]"))]
        ];
        proof.c = [vm.parseUint(proofJson.readString(".pi_c[0]")), vm.parseUint(proofJson.readString(".pi_c[1]"))];

        signals[0] = vm.parseUint(publicJson.readString(".signals[0]"));
        signals[1] = vm.parseUint(publicJson.readString(".signals[1]"));
        signals[2] = vm.parseUint(publicJson.readString(".signals[2]"));
    }

    function _readFileViaCat(string memory path) internal returns (string memory) {
        string[] memory cmd = new string[](2);
        cmd[0] = "cat";
        cmd[1] = path;
        Vm.FfiResult memory res = vm.tryFfi(cmd);
        require(res.exitCode == 0, string.concat("cat failed: ", string(res.stderr)));
        return string(res.stdout);
    }

    function _isSnarkjsInstalled() internal returns (bool) {
        string[] memory whichCmd = new string[](2);
        whichCmd[0] = "which";
        whichCmd[1] = "snarkjs";
        Vm.FfiResult memory whichRes = vm.tryFfi(whichCmd);
        return whichRes.exitCode == 0;
    }

    function _buildSequentialBlob(uint256 start, uint256 length) internal pure returns (bytes memory blob) {
        blob = new bytes(length * 32);
        for (uint256 i = 0; i < length; i++) {
            bytes32 entry = _encodeBytes32String(start + i);
            assembly ("memory-safe") {
                mstore(add(add(blob, 32), mul(i, 32)), entry)
            }
        }
    }

    function _encodeBytes32String(uint256 value) internal pure returns (bytes32 result) {
        string memory str = Strings.toString(value);
        bytes memory strBytes = bytes(str);
        assembly ("memory-safe") {
            result := mload(add(strBytes, 32))
        }
    }

    function _loadChunk(bytes memory blob, uint256 chunkIdx) internal pure returns (bytes32 word) {
        assembly ("memory-safe") {
            word := mload(add(add(blob, 32), mul(chunkIdx, 32)))
        }
    }

    function _encodeProof(Groth16Proof memory proof) internal pure returns (bytes memory) {
        return abi.encode(proof.a, proof.b, proof.c);
    }

    function _encodeInclusiveProof(bytes32 dataWord, bytes32 root, bytes32[] memory proof)
        internal
        pure
        returns (bytes memory)
    {
        TestEthStorageContractM1.MerkleProof memory mProof =
            TestEthStorageContractM1.MerkleProof({data: dataWord, rootHash: root, proofs: proof});
        return abi.encode(mProof);
    }

    function _computeEncodingKey(bytes memory blob, address miner, uint256 kvIdx) internal pure returns (bytes32) {
        bytes32 root = MerkleLib.merkleRootWithMinTree(blob, 32);
        bytes memory rootBytes = abi.encodePacked(root);
        for (uint256 i = 24; i < 32; i++) {
            rootBytes[i] = 0;
        }
        bytes32 truncated;
        assembly ("memory-safe") {
            truncated := mload(add(rootBytes, 32))
        }
        return keccak256(abi.encode(truncated, miner, kvIdx));
    }

    function _decodeProofSample123() internal pure returns (Groth16Proof memory) {
        return Groth16Proof({
            a: [
                uint256(0x1282d54b7ca32fb9322b14d22b9ed8d8d74a2fa8199fc9b33f692175a0151dfa),
                uint256(0x2ec90d197f18a88c179a7371d60523308e23239a418cc6f3140683d32f3038c6)
            ],
            b: [
                [
                    uint256(0x1ad0f63458899201b8e4b6ac99745f56a2e3fcb31059daa6316c9bbc1ff98796),
                    uint256(0x06d74f531689723f5bf1256e182cd6c39e5bf31343528cd9ba52e94fadb69c2a)
                ],
                [
                    uint256(0x2bda468dd57d4542b63c1039bebe6308533bd64976bd6820a776a505a601e7f0),
                    uint256(0x1e8b561f1b9aa9ccf3b9fc5178af00b4def50189b4241b24b1437540e71078fa)
                ]
            ],
            c: [
                uint256(0x2f53719313a92f79ab72d1c9191186ffa20f553b8340070f5f6c120d9e07eefa),
                uint256(0x2f89e19298611c499aa59fb59f3b0f4459378ca83b13facc2981fa396d202e1c)
            ]
        });
    }

    function _decodeProofSample84() internal pure returns (Groth16Proof memory) {
        return Groth16Proof({
            a: [
                uint256(0x08f2b57a05c4e7d93db6d445a8f41d13d3c7d07ec74b95a2aad5f6400eda803a),
                uint256(0x1512576a70dc873c5d70d21b584e88f9f497390dc710a0416ef505e39d6954da)
            ],
            b: [
                [
                    uint256(0x1211829efb3afc4a217212703937cad70a4f21db1e6710afe61f7f9e4ea5ba22),
                    uint256(0x01a824f4a072f732a75aa03e89eb5ed299a0d18027ab30eda0961f02e37019b3)
                ],
                [
                    uint256(0x0a41eb1f5a366f1bbb948ffd77671da0e372b6b7b6cfb6e702e90e5d4370cbf2),
                    uint256(0x1e3588c5a06df2a1bcfa1cf57e12d46b5cfa0e21e634b897656fcbae6d08225b)
                ]
            ],
            c: [
                uint256(0x05cad4a375ea33e595a342771c9eb46503dac95de18e38beef5f3186fbdd2a2f),
                uint256(0x281d9c7b0edc98c9377ce751601d4fd6a2c925b0912d53436fd3eb84f0a67205)
            ]
        });
    }

    function _decodeProofNext() internal pure returns (Groth16Proof memory) {
        return Groth16Proof({
            a: [
                uint256(0x2505556e329c539570d437dee5e76b753d94c98988bdbd8466131c993bf0e459),
                uint256(0x19a70541e1fb2436fbb2e9f7b444515f8b7831dbe1731b1d34a2aeec92d1fba9)
            ],
            b: [
                [
                    uint256(0x20ea125a8fbadc14fa99bb19497b065383d814bb7452227bdeae152c60145267),
                    uint256(0x293b93976a31d8f79d1896b12dbc377fc05b15aac014a79009ea0e39378ede8c)
                ],
                [
                    uint256(0x2b86da20245342b62e5e0b837c814cb11962b8a7c7489747c953c0f629602826),
                    uint256(0x1e26c4ca8d1f77d3bda5ff318fc315158ebea7701e9be700063b1a859390a06e)
                ]
            ],
            c: [
                uint256(0x11e399c647363330c3327223bd188712eb4bc84b7f00d0ae48decb8cc26822fd),
                uint256(0x2b37fb4fbe73864fbb824c06e920b11bcc2a91e5bc9e93ca01b2899426882e6f)
            ]
        });
    }
}
