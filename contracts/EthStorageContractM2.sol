// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./EthStorageContract.sol";
import "./zk-verify/Decoder2.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @custom:proxied
/// @title EthStorageContract2
/// @notice EthStorage Contract that verifies two sample decodings using only one zk proof
contract EthStorageContractM2 is Initializable, EthStorageContract, Decoder2 {
    /// @notice Constructs the EthStorageContractM2 contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the EthStorageContractM2 contract.
    function initialize(
        Config memory _config,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor,
        uint256 _minimumDiff,
        uint256 _prepaidAmount,
        uint256 _nonceLimit,
        address _treasury,
        address _admin
    ) public initializer {
        __init_eth_storage(
            _config, _startTime, _storageCost, _dcfFactor, _minimumDiff, _prepaidAmount, _nonceLimit, _treasury, _admin
        );
    }

    /// @notice Verify the masks using the zk proof
    /// @param _masks The masks for the samples
    /// @param _kvIdxs The kvIdxs that contain the samples
    /// @param _sampleIdxs The sampleIdxs in the kvIdxs
    /// @param _miner The miner address
    /// @param _decodeProof The zk proof for two sample decoding
    /// @return true if the proof is valid, false otherwise
    function decodeSamples(
        uint256[] memory _masks,
        uint256[] memory _kvIdxs,
        uint256[] memory _sampleIdxs,
        address _miner,
        bytes calldata _decodeProof
    ) public view returns (bool) {
        (uint256[2] memory pA, uint256[2][2] memory pB, uint256[2] memory pC) =
            abi.decode(_decodeProof, (uint256[2], uint256[2][2], uint256[2]));

        uint256[6] memory pubSignals;
        pubSignals[0] = _getEncodingKey(_kvIdxs[0], _miner);
        pubSignals[1] = _getEncodingKey(_kvIdxs[1], _miner);
        pubSignals[2] = _getXIn(_sampleIdxs[0]);
        pubSignals[3] = _getXIn(_sampleIdxs[1]);
        pubSignals[4] = _masks[0];
        pubSignals[5] = _masks[1];
        // verifyProof uses the opcode 'return', so if we call verifyProof directly, it will lead to a compiler warning about 'unreachable code'
        // and causes the caller function return directly
        return this.verifyProof(pA, pB, pC, pubSignals);
    }

    /// @notice Check the sample is included in the kvIdx
    /// @param _startShardId The start shard id
    /// @param _rows The number of samples per shard
    /// @param _hash0 The hash0 value
    /// @param _encodedSample The encoded sample data
    /// @param _mask The mask for the sample
    /// @param _inclusiveProof The zk proof for the sample inclusion
    /// @return The next hash0 value
    /// @return The kvIdx that contains the sample
    /// @return The sampleIdx in the kvIdx
    function _checkSample(
        uint256 _startShardId,
        uint256 _rows,
        bytes32 _hash0,
        bytes32 _encodedSample,
        uint256 _mask,
        bytes calldata _inclusiveProof
    ) internal view returns (bytes32, uint256, uint256) {
        (uint256 kvIdx, uint256 sampleIdxInKv) = getSampleIdx(_rows, _startShardId, _hash0);

        PhyAddr memory kvInfo = kvMap[idxMap[kvIdx]];

        require(
            checkInclusive(kvInfo.hash, sampleIdxInKv, _mask ^ uint256(_encodedSample), _inclusiveProof),
            "EthStorageContractM2: invalid samples"
        );
        _hash0 = keccak256(abi.encode(_hash0, _encodedSample));
        return (_hash0, kvIdx, sampleIdxInKv);
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
        require(_encodedSamples.length == RANDOM_CHECKS, "EthStorageContractM2: data length mismatch");
        require(_masks.length == RANDOM_CHECKS, "EthStorageContractM2: masks length mismatch");
        require(_inclusiveProofs.length == RANDOM_CHECKS, "EthStorageContractM2: proof length mismatch");
        require(_decodeProof.length == 1, "EthStorageContractM2: decodeProof length mismatch");
        // calculate the number of samples range of the sample check
        uint256 rows = 1 << (SHARD_ENTRY_BITS + SAMPLE_LEN_BITS);

        uint256[] memory kvIdxs = new uint256[](RANDOM_CHECKS);
        uint256[] memory sampleIdxs = new uint256[](RANDOM_CHECKS);
        for (uint256 i = 0; i < RANDOM_CHECKS; i++) {
            (_hash0, kvIdxs[i], sampleIdxs[i]) =
                _checkSample(_startShardId, rows, _hash0, _encodedSamples[i], _masks[i], _inclusiveProofs[i]);
        }

        require(
            decodeSamples(_masks, kvIdxs, sampleIdxs, _miner, _decodeProof[0]), "EthStorageContractM2: decode failed"
        );
        return _hash0;
    }
}
