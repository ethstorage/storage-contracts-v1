// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract.sol";
import "./MerkleLib.sol";

contract TestEthStorageContract is EthStorageContract {
    uint256 public currentTimestamp;

    struct MerkleProof {
        bytes32 data;
        bytes32 rootHash;
        bytes32[] proofs;
    }

    constructor(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _nonceLimit,
        address _treasury,
        uint256 _prepaidAmount
    ) EthStorageContract(_config, _startTime, _storageCost, _dcfFactor, _nonceLimit, _treasury, _prepaidAmount) {}

    function setTimestamp(uint256 ts) public {
        require(ts > currentTimestamp, "ts");
        currentTimestamp = ts;
    }

    function put(bytes32 key, bytes memory data) public payable {
        bytes32 dataHash = MerkleLib.merkleRootWithMinTree(data, 32); // TODO: 64-bytes should be more efficient.
        _putInternal(key, dataHash, data.length);
    }

    /*
     * Decode the sample and check the decoded sample is included in the BLOB corresponding to on-chain datahashes.
     */
    function decodeAndCheckInclusive(
        uint256 kvIdx,
        uint256 sampleIdxInKv,
        PhyAddr memory kvInfo,
        address miner,
        bytes32 encodedData,
        bytes calldata inclusiveProof
    ) public view virtual override returns (bool) {
        (Proof memory proof, uint256 mask, MerkleProof memory mProof) = abi.decode(
            inclusiveProof,
            (Proof, uint256, MerkleProof)
        );

        // BLOB decoding check
        if (!decodeSample(proof, uint256(keccak256(abi.encode(kvInfo.hash, miner, kvIdx))), sampleIdxInKv, mask)) {
            return false;
        }

        // Inclusive proof of decodedData = mask ^ encodedData
        if (!MerkleLib.verify(keccak256(abi.encode(mProof.data)), sampleIdxInKv, mProof.rootHash, mProof.proofs)) {
            return false;
        }

        uint256 expectedEncodedData = uint256(mProof.data) ^ mask;
        return bytes32(expectedEncodedData) == encodedData;
    }
}
