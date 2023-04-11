// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStorageManager {
    // Get a raw data from underlying storage.
    function getRaw(
        bytes32 hash,
        uint256 kvIdx,
        uint256 off,
        uint256 len
    ) external view returns (bytes memory);

    // Set a raw data to underlying storage.
    function putRaw(uint256 kvIdx, bytes memory data) external;

    // Remove by moving data from fromKvIdx to toKvIdx and clear fromKvIdx
    function removeRaw(uint256 fromKvIdx, uint256 toKvIdx) external;
}

interface IMiningHash {
    // A CPU-intensive hash algorithm used to generate random KV indices.
    function hash0(bytes32) external view returns (bytes32);

    // Return the masked hash of data.
    // Only return hash of [0, len) bytes after unmasking, assuming the rest bytes are zeros.
    // Return 0x0 if the rest unmasked data have non-zero bytes.
    // Use batched method that allow concurrent computation.
    function maskedDataHashes(
        uint256[] memory kvIdxs,
        uint256[] memory kvSizes,
        bytes[] memory data
    ) external view returns (bytes32[] memory);
}

interface IDaggerHash {
    // Decode the data and return raw data that verfier needs
    function unmaskChunkWithEthash(
        uint64 chunkIdx,
        bytes24 kvHash,
        address miner,
        bytes memory maskedChunk
    ) external view returns (bytes memory);

    // Another option is to use Verify Delay Function(VDF),
    // such as MiMC. For saving gas cost, those are not materialized for now
    function unmaskWithEthash(uint256 kvIdx, bytes memory maskedData) external view returns (bytes memory);
}

interface ISystemContract is IStorageManager, IMiningHash {}

interface ISystemContractDaggerHashimoto is IStorageManager, IDaggerHash {}
