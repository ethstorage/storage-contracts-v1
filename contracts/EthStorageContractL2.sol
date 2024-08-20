// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthStorageContract2.sol";

/// @title IL1Block
/// @notice Interface for L1Block contract.
interface IL1Block {
    /// @notice Get the blockhash of an L1 history block number.
    /// @param _historyNumber The L1 history block number.
    /// @return The blockhash of the L1 history block number.
    function blockHash(uint256 _historyNumber) external view returns (bytes32);

    /// @notice Get the current L1 block number.
    /// @return The current L1 block number.
    function number() external view returns (uint64);

    /// @notice Get the current L1 block timestamp.
    /// @return The current L1 block timestamp.
    function timestamp() external view returns (uint64);
}

/// @custom:proxied
/// @title EthStorageContractL2
/// @notice EthStorage contract that will be deployed on L2, and uses L1Block contract to mine.
contract EthStorageContractL2 is EthStorageContract2 {
    /// @notice The precompile contract address for L1Block.
    IL1Block internal constant L1_BLOCK = IL1Block(0x4200000000000000000000000000000000000015);

    /// @notice Constructs the EthStorageContractL2 contract.
    constructor(Config memory _config, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor)
        EthStorageContract2(_config, _startTime, _storageCost, _dcfFactor)
    {}

    /// @notice Get the current block number
    function blockNumber() internal view override returns (uint256) {
        return L1_BLOCK.number();
    }

    /// @notice Get the current block timestamp
    function blockTs() internal view override returns (uint256) {
        return L1_BLOCK.timestamp();
    }

    /// @notice Get the randao value from the L1 blockhash.
    function getRandao(uint256 _l1BlockNumber, bytes calldata _headerRlpBytes)
        internal
        view
        override
        returns (bytes32)
    {
        bytes32 bh = L1_BLOCK.blockHash(_l1BlockNumber);
        require(bh != bytes32(0), "EthStorageContractL2: failed to obtain blockhash");
        return RandaoLib.verifyHeaderAndGetRandao(bh, _headerRlpBytes);
    }
}
