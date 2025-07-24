// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./EthStorageContract.sol";
import "./zk-verify/Decoder.sol";

/// @custom:proxied
/// @title EthStorageContract1
/// @notice EthStorage Contract that verifies sample decodings per zk proof
contract EthStorageContract1 is EthStorageContract, Decoder {
    /// @notice Constructs the EthStorageContract1 contract.
    constructor(Config memory _config, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor)
        EthStorageContract(_config, _startTime, _storageCost, _dcfFactor)
    {}

    /// @notice Verify the mask is correct
    /// @param _proof The ZK proof
    /// @param _encodingKey The encoding key
    /// @param _sampleIdxInKv The sample index in the KV
    /// @param _mask The mask of the sample
    /// @return The result of the verification
    function decodeSample(bytes memory _proof, uint256 _encodingKey, uint256 _sampleIdxInKv, uint256 _mask)
        public
        view
        returns (bool)
    {
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC) =
            abi.decode(_proof, (uint256[2], uint256[2][2], uint256[2]));

        uint256 xBn254 = _modExp(RU_BN254, _sampleIdxInKv, MODULUS_BN254);

        // TODO: simple hash to curve mapping
        return this.verifyProof(pA, pB, pC, [_encodingKey % MODULUS_BN254, xBn254, _mask]);
    }

    /// @notice Decode the sample and check the decoded sample is included in the BLOB corresponding to on-chain datahashes
    /// @param _kvIdx The index of the KV pair
    /// @param _sampleIdxInKv The sample index in the KV
    /// @param _miner The miner address
    /// @param _encodedData The encoded sample data
    /// @param _mask The mask of the sample
    /// @param _inclusiveProof The inclusive proof
    /// @param _decodeProof The decode proof
    /// @return The result of the check
    function decodeAndCheckInclusive(
        uint256 _kvIdx,
        uint256 _sampleIdxInKv,
        address _miner,
        bytes32 _encodedData,
        uint256 _mask,
        bytes calldata _inclusiveProof,
        bytes calldata _decodeProof
    ) public view virtual returns (bool) {
        PhyAddr memory kvInfo = kvMap[idxMap[_kvIdx]];
        // BLOB decoding check
        if (
            !decodeSample(
                _decodeProof, uint256(keccak256(abi.encode(kvInfo.hash, _miner, _kvIdx))), _sampleIdxInKv, _mask
            )
        ) {
            return false;
        }

        // Inclusive proof of decodedData = mask ^ encodedData
        return checkInclusive(kvInfo.hash, _sampleIdxInKv, _mask ^ uint256(_encodedData), _inclusiveProof);
    }

    /// @inheritdoc StorageContract
    function verifySamples(
        uint256 _startShardId,
        bytes32 _hash0,
        address _miner,
        bytes32[] memory _encodedSamples,
        uint256[] memory _masks,
        bytes[] calldata _inclusiveProofs,
        bytes[] calldata _decodeProof
    ) public view virtual override returns (bytes32) {
        require(_encodedSamples.length == RANDOM_CHECKS, "EthStorageContract1: data length mismatch");
        require(_masks.length == RANDOM_CHECKS, "EthStorageContract1: masks length mismatch");
        require(_inclusiveProofs.length == RANDOM_CHECKS, "EthStorageContract1: proof length mismatch");
        require(_decodeProof.length == RANDOM_CHECKS, "EthStorageContract1: decodeProof length mismatch");

        // calculate the number of samples range of the sample check
        uint256 rows = 1 << (SHARD_ENTRY_BITS + SAMPLE_LEN_BITS);

        for (uint256 i = 0; i < RANDOM_CHECKS; i++) {
            (uint256 kvIdx, uint256 sampleIdxInKv) = getSampleIdx(rows, _startShardId, _hash0);

            require(
                decodeAndCheckInclusive(
                    kvIdx, sampleIdxInKv, _miner, _encodedSamples[i], _masks[i], _inclusiveProofs[i], _decodeProof[i]
                ),
                "EthStorageContract1: invalid samples"
            );
            _hash0 = keccak256(abi.encode(_hash0, _encodedSamples[i]));
        }
        return _hash0;
    }
}
