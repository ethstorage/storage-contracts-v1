// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./StorageContract.sol";
import "./zk-verify/Decoder.sol";
import "./libraries//BinaryRelated.sol";
import "./Interfaces/ISemver.sol";

/// @custom:proxied
/// @title EthStorageContract
/// @notice EthStorage Contract that using EIP-4844 BLOB
contract EthStorageContract is StorageContract, Decoder, ISemver {
    /// @notice The modulus for the BLS curve
    uint256 internal constant MODULUS_BLS = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001;

    /// @notice The root of unity of BLS curve
    uint256 internal constant RU_BLS = 0x564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d36306;

    /// @notice The root of unity for the BN254 curve
    uint256 constant RU_BN254 = 0x931d596de2fd10f01ddd073fd5a90a976f169c76f039bb91c4775720042d43a;

    /// @notice The modulus for the BN254 curve
    uint256 constant MODULUS_BN254 = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;

    /// @notice The field elements per BLOB
    uint256 constant FIELD_ELEMENTS_PER_BLOB = 0x1000;

    /// @notice Semantic version.
    /// @custom:semver 0.1.1
    string public constant version = "0.1.1";

    // TODO: Reserve extra slots (to a total of 50?) in the storage layout for future upgrades

    /// @notice Emitted when a BLOB is appended.
    /// @param kvIdx    The index of the KV pair
    /// @param kvSize   The size of the KV pair
    /// @param dataHash The hash of the data
    event PutBlob(uint256 indexed kvIdx, uint256 indexed kvSize, bytes32 indexed dataHash);

    /// @notice Constructs the EthStorageContract contract.
    constructor(Config memory _config, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor)
        StorageContract(_config, _startTime, _storageCost, _dcfFactor)
    {
        _disableInitializers();
    }

    /// @notice Initialize the contract
    function initialize(
        uint256 _minimumDiff,
        uint256 _prepaidAmount,
        uint256 _nonceLimit,
        address _treasury,
        address _owner
    ) public payable initializer {
        __init_storage(_minimumDiff, _prepaidAmount, _nonceLimit, _treasury, _owner);
    }

    /// @notice Performs modular exponentiation, which is a type of exponentiation performed over a modulus.
    /// @param _b The base
    /// @param _e The exponent
    /// @param _m The modulus
    /// @return result_ The result of the modular exponentiation
    function _modExp(uint256 _b, uint256 _e, uint256 _m) internal view returns (uint256 result_) {
        assembly {
            // Free memory pointer
            let pointer := mload(0x40)

            // Define length of base, exponent and modulus. 0x20 == 32 bytes
            mstore(pointer, 0x20)
            mstore(add(pointer, 0x20), 0x20)
            mstore(add(pointer, 0x40), 0x20)

            // Define variables base, exponent and modulus
            mstore(add(pointer, 0x60), _b)
            mstore(add(pointer, 0x80), _e)
            mstore(add(pointer, 0xa0), _m)

            // Call the precompiled contract 0x05 = bigModExp, reuse scratch to get the results
            if iszero(staticcall(not(0), 0x05, pointer, 0xc0, 0x0, 0x20)) { revert(0, 0) }

            result_ := mload(0x0)

            // Clear memory or exclude the memory
            mstore(0x40, add(pointer, 0xc0))
        }
    }

    /// @notice Perform point evaluation
    /// @param _input The input data
    /// @return versionedHash_ The versioned hash
    /// @return x_ The x coordinate
    /// @return y_ The y coordinate
    function _pointEvaluation(bytes memory _input)
        internal
        view
        returns (uint256 versionedHash_, uint256 x_, uint256 y_)
    {
        assembly {
            versionedHash_ := mload(add(_input, 0x20))
            x_ := mload(add(_input, 0x40))
            y_ := mload(add(_input, 0x60))

            // Call the precompiled contract 0x0a = point evaluation, reuse scratch to get the results
            if iszero(staticcall(not(0), 0x0a, add(_input, 0x20), 0xc0, 0x0, 0x40)) { revert(0, 0) }
            // Check the results
            if iszero(eq(mload(0x0), FIELD_ELEMENTS_PER_BLOB)) { revert(0, 0) }
            if iszero(eq(mload(0x20), MODULUS_BLS)) { revert(0, 0) }
        }
    }

    /// @notice Verify the mask is correct
    /// @param _proof The ZK proof
    /// @param _encodingKey The encoding key
    /// @param _sampleIdxInKv The sample index in the KV
    /// @param _mask The mask of the sample
    /// @return The result of the verification
    function decodeSample(Proof memory _proof, uint256 _encodingKey, uint256 _sampleIdxInKv, uint256 _mask)
        public
        view
        returns (bool)
    {
        uint256 xBn254 = _modExp(RU_BN254, _sampleIdxInKv, MODULUS_BN254);

        uint256[] memory input = new uint256[](3);
        // TODO: simple hash to curve mapping
        input[0] = _encodingKey % MODULUS_BN254;
        input[1] = xBn254;
        input[2] = _mask;
        return (verifyDecoding(input, _proof) == 0);
    }

    /// @notice Check the decoded data is included in the BLOB corresponding to on-chain datahashes
    /// @param _dataHash The data hash
    /// @param _sampleIdxInKv The sample index in the KV
    /// @param _decodedData The decoded sample
    /// @param _peInput The point evaluation input
    /// @return The result of the check
    function checkInclusive(bytes32 _dataHash, uint256 _sampleIdxInKv, uint256 _decodedData, bytes memory _peInput)
        public
        view
        returns (bool)
    {
        if (_dataHash == 0x0) {
            return _decodedData == 0;
        }
        // peInput includes an input point that comes from bit reversed sampleIdxInKv
        uint256 sampleIdxInKvRev = BinaryRelated.reverseBits(12, _sampleIdxInKv);
        uint256 xBls = _modExp(RU_BLS, sampleIdxInKvRev, MODULUS_BLS);
        (uint256 versionedHash, uint256 evalX, uint256 evalY) = _pointEvaluation(_peInput);
        if (evalX != xBls || bytes24(bytes32(versionedHash)) != _dataHash) {
            return false;
        }

        return evalY == _decodedData;
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
        Proof memory proof = abi.decode(_decodeProof, (Proof));
        // BLOB decoding check
        if (!decodeSample(proof, uint256(keccak256(abi.encode(kvInfo.hash, _miner, _kvIdx))), _sampleIdxInKv, _mask)) {
            return false;
        }

        // Inclusive proof of decodedData = mask ^ encodedData
        return checkInclusive(kvInfo.hash, _sampleIdxInKv, _mask ^ uint256(_encodedData), _inclusiveProof);
    }

    /// @notice Get the sample index
    /// @param _rows The sample count per shard
    /// @param _startShardId The start shard ID
    /// @param _hash0 The hash0
    /// @return The key index contains the sample
    /// @return The sample index in the key
    function getSampleIdx(uint256 _rows, uint256 _startShardId, bytes32 _hash0)
        public
        view
        returns (uint256, uint256)
    {
        uint256 parent = uint256(_hash0) % _rows;
        uint256 sampleIdx = parent + (_startShardId << (SHARD_ENTRY_BITS + SAMPLE_LEN_BITS));
        uint256 kvIdx = sampleIdx >> SAMPLE_LEN_BITS;
        uint256 sampleIdxInKv = sampleIdx % (1 << SAMPLE_LEN_BITS);
        return (kvIdx, sampleIdxInKv);
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
        require(_encodedSamples.length == RANDOM_CHECKS, "EthStorageContract: data length mismatch");
        require(_masks.length == RANDOM_CHECKS, "EthStorageContract: masks length mismatch");
        require(_inclusiveProofs.length == RANDOM_CHECKS, "EthStorageContract: proof length mismatch");
        require(_decodeProof.length == RANDOM_CHECKS, "EthStorageContract: decodeProof length mismatch");

        // calculate the number of samples range of the sample check
        uint256 rows = 1 << (SHARD_ENTRY_BITS + SAMPLE_LEN_BITS);

        for (uint256 i = 0; i < RANDOM_CHECKS; i++) {
            (uint256 kvIdx, uint256 sampleIdxInKv) = getSampleIdx(rows, _startShardId, _hash0);

            require(
                decodeAndCheckInclusive(
                    kvIdx, sampleIdxInKv, _miner, _encodedSamples[i], _masks[i], _inclusiveProofs[i], _decodeProof[i]
                ),
                "EthStorageContract: invalid samples"
            );
            _hash0 = keccak256(abi.encode(_hash0, _encodedSamples[i]));
        }
        return _hash0;
    }

    /// @notice Write a large value to KV store.  If the KV pair exists, overrides it.
    ///         Otherwise, will append the KV to the KV array.
    /// @param _key The key of the KV pair
    /// @param _blobIdx The index of the blob
    /// @param _length The length of the blob
    function putBlob(bytes32 _key, uint256 _blobIdx, uint256 _length) public payable virtual {
        bytes32 dataHash = blobhash(_blobIdx);
        require(dataHash != 0, "EthStorageContract: failed to get blob hash");

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = _key;
        bytes32[] memory dataHashes = new bytes32[](1);
        dataHashes[0] = dataHash;
        uint256[] memory lengths = new uint256[](1);
        lengths[0] = _length;

        uint256[] memory kvIndices = _putBatchInternal(keys, dataHashes, lengths);

        emit PutBlob(kvIndices[0], _length, dataHash);
    }

    /// @notice Write multiple large values to KV store.
    /// @param _keys The keys of the KV pairs
    /// @param _blobIdxs The indexes of the blobs
    /// @param _lengths The lengths of the blobs
    function putBlobs(bytes32[] memory _keys, uint256[] memory _blobIdxs, uint256[] memory _lengths)
        public
        payable
        virtual
    {
        require(
            _keys.length == _blobIdxs.length && _keys.length == _lengths.length,
            "EthStorageContract: input length mismatch"
        );

        bytes32[] memory dataHashes = new bytes32[](_blobIdxs.length);
        for (uint256 i = 0; i < _blobIdxs.length; i++) {
            dataHashes[i] = blobhash(_blobIdxs[i]);
            require(dataHashes[i] != 0, "EthStorageContract: failed to get blob hash");
        }

        uint256[] memory kvIdxs = _putBatchInternal(_keys, dataHashes, _lengths);

        for (uint256 i = 0; i < _blobIdxs.length; i++) {
            emit PutBlob(kvIdxs[i], _lengths[i], dataHashes[i]);
        }
    }
}
