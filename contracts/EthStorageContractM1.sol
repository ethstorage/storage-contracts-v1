// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./EthStorageContract.sol";
import "./zk-verify/Decoder.sol";

/// @custom:proxied
/// @title EthStorageContractM1
/// @notice EthStorage Contract that verifies sample decodings per zk proof
contract EthStorageContractM1 is EthStorageContract, Decoder {
    /// @notice Thrown when the input length is mismatched.
    error EthStorageContractM1_LengthMismatch();

    /// @notice Thrown when the decoding of a sample fails.
    error EthStorageContractM1_DecodeSampleFailed();

    /// @notice Thrown when the samples are invalid.
    error EthStorageContractM1_InvalidSamples();

    /// @notice Constructs the EthStorageContractM1 contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(Config memory _config, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor)
        EthStorageContract(_config, _startTime, _storageCost, _dcfFactor)
    {}

    /// @notice Initialize the contract
    function initialize(
        uint256 _minimumDiff,
        uint256 _prepaidAmount,
        uint256 _nonceLimit,
        address _treasury,
        address _admin
    ) public payable virtual override initializer {
        super.initialize(_minimumDiff, _prepaidAmount, _nonceLimit, _treasury, _admin);
    }

    /// @notice Verify the masks using the zk proof
    /// @param _mask The mask for the sample
    /// @param _kvIdx The kvIdx that contain the sample
    /// @param _sampleIdx The sampleIdx in the kvIdx
    /// @param _miner The miner address
    /// @param _decodeProof The zk proof for the sample decoding
    /// @return true if the proof is valid, false otherwise
    function decodeSample(
        uint256 _mask,
        uint256 _kvIdx,
        uint256 _sampleIdx,
        address _miner,
        bytes calldata _decodeProof
    ) public view returns (bool) {
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC) =
            abi.decode(_decodeProof, (uint256[2], uint256[2][2], uint256[2]));

        uint256[3] memory pubSignals;
        pubSignals[0] = _getEncodingKey(_kvIdx, _miner);
        pubSignals[1] = _getXIn(_sampleIdx);
        pubSignals[2] = _mask;
        // TODO: simple hash to curve mapping
        return this.verifyProof(pA, pB, pC, pubSignals);
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
        if (
            _encodedSamples.length != RANDOM_CHECKS || _masks.length != RANDOM_CHECKS
                || _inclusiveProofs.length != RANDOM_CHECKS || _decodeProof.length != RANDOM_CHECKS
        ) {
            revert EthStorageContractM1_LengthMismatch();
        }

        // calculate the number of samples range of the sample check
        uint256 rows = 1 << (SHARD_ENTRY_BITS + SAMPLE_LEN_BITS);

        for (uint256 i = 0; i < RANDOM_CHECKS; i++) {
            (uint256 kvIdx, uint256 sampleIdxInKv) = getSampleIdx(rows, _startShardId, _hash0);

            if (!decodeSample(_masks[i], kvIdx, sampleIdxInKv, _miner, _decodeProof[i])) {
                revert EthStorageContractM1_DecodeSampleFailed();
            }
            // Inclusive proof of decodedData = mask ^ encodedData
            if (
                !checkInclusive(
                    _kvMap(_idxMap(kvIdx)).hash,
                    sampleIdxInKv,
                    _masks[i] ^ uint256(_encodedSamples[i]),
                    _inclusiveProofs[i]
                )
            ) {
                revert EthStorageContractM1_InvalidSamples();
            }

            _hash0 = keccak256(abi.encode(_hash0, _encodedSamples[i]));
        }
        return _hash0;
    }
}
