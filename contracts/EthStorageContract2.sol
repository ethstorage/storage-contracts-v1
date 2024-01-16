// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract.sol";
import "./Decoder2.sol";


contract EthStorageContract2 is EthStorageContract, Decoder2 {

    function getEncodingKey(uint256 kvIdx, address miner) internal view returns (uint256) {
        return uint256(keccak256(abi.encode(kvMap[idxMap[kvIdx]].hash, miner, kvIdx)));
    }

    function getXIn(uint256 sampleIdx) internal view returns (uint256) {
        return modExp(ruBn254, sampleIdx, modulusBn254);
    }

    function _decodeSample(bytes calldata decodeProof, uint[6] memory _pubSignals) internal view returns (bool) {
        (uint[2] memory pA, uint[2][2] memory pB, uint[2] memory pC) = abi.decode(decodeProof, (uint[2], uint[2][2], uint[2]));
        // verifyProof uses the opcode 'return', so if we call verifyProof directly, it will lead to a compiler warning about 'unreachable code' 
        // and causes the caller function return directly        
        return this.verifyProof(pA, pB, pC, _pubSignals);
    }

    function decodeSample(
        uint256[] memory masks,
        uint256[] memory kvIdxs,
        uint256[] memory sampleIdxs,
        address miner,
        bytes calldata decodeProof
    ) public view returns (bool) {
        return _decodeSample(decodeProof, [
            getEncodingKey(kvIdxs[0], miner),
            getEncodingKey(kvIdxs[1], miner),
            getXIn(sampleIdxs[0]),
            getXIn(sampleIdxs[1]),
            masks[0],
            masks[1]
        ]);
    }

    function _checkSample(
        uint256 startShardId, 
        uint256 rows, 
        bytes32 hash0,
        bytes32 encodedSamples,
        uint256 masks,
        bytes calldata inclusiveProofs
    ) internal view returns (bytes32, uint256, uint256) {
        (uint256 kvIdx, uint256 sampleIdxInKv) = getSampleIdx(rows, startShardId, hash0);
                
        PhyAddr memory kvInfo = kvMap[idxMap[kvIdx]];

        require(
            checkInclusive(kvInfo.hash, sampleIdxInKv, masks ^ uint256(encodedSamples), inclusiveProofs),
            "invalid samples"
        );
        hash0 = keccak256(abi.encode(hash0, encodedSamples));
        return (hash0, kvIdx, sampleIdxInKv);
    }

    function verifySamples(
        uint256 startShardId,
        bytes32 hash0,
        address miner,
        bytes32[] memory encodedSamples,
        uint256[] memory masks,
        bytes[] calldata inclusiveProofs,
        bytes[] calldata decodeProof
    ) public view virtual override returns (bytes32) {
        require(encodedSamples.length == randomChecks, "data length mismatch");
        require(masks.length == randomChecks, "masks length mismatch");
        require(inclusiveProofs.length == randomChecks, "proof length mismatch");
        require(decodeProof.length == 1, "decodeProof length mismatch");
        // calculate the number of samples range of the sample check
        uint256 rows = 1 << (shardEntryBits + sampleLenBits);

        uint[] memory kvIdxs = new uint[](randomChecks);
        uint[] memory sampleIdxs = new uint[](randomChecks);
        for (uint256 i = 0; i < randomChecks; i++) {
            (hash0, kvIdxs[i], sampleIdxs[i]) = _checkSample(
                startShardId, 
                rows, 
                hash0, 
                encodedSamples[i], 
                masks[i], 
                inclusiveProofs[i]
            );
        }

        require(decodeSample(masks, kvIdxs, sampleIdxs, miner, decodeProof[0]), "decode failed");
        return hash0;
    }
} 
