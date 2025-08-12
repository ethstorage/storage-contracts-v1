// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./libraries/RandaoLib.sol";

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

/// @title ISoulGasToken
/// @notice Interface for the SoulGasToken contract.
interface ISoulGasToken {
    function chargeFromOrigin(uint256 _amount) external returns (uint256);
}

/// @custom:proxied
/// @title L2Base
/// @notice Common base contract that will be deployed on L2, and uses L1Block contract to mine.
abstract contract L2Base {
    /// @notice The precompile contract address for L1Block.
    IL1Block internal constant L1_BLOCK = IL1Block(0x4200000000000000000000000000000000000015);

    /// @notice The mask to extract `blockLastUpdate`
    uint256 internal constant MASK = ~uint256(0) ^ type(uint32).max;

    /// @notice The rate limit to update blobs per block
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 internal immutable UPDATE_LIMIT;

    /// @notice A slot to store both `blockLastUpdate` (left 224) and `blobsUpdated` (right 32)
    uint256 internal updateState;

    /// @notice The address of the soul gas token.
    address public soulGasToken;

    /// @notice Constructs the L2Base contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 _updateLimit) {
        UPDATE_LIMIT = _updateLimit;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @notice Set the soul gas token address for the contract.
    function _setSoulGasToken(address _soulGasToken) internal {
        soulGasToken = _soulGasToken;
    }

    /// @notice Get the current block number
    function _blockNumber() internal view virtual returns (uint256) {
        return L1_BLOCK.number();
    }

    /// @notice Get the current block timestamp
    function _blockTs() internal view virtual returns (uint256) {
        return L1_BLOCK.timestamp();
    }

    /// @notice Get the randao value from the L1 blockhash.
    function _getRandao(uint256 _l1BlockNumber, bytes calldata _headerRlpBytes)
        internal
        view
        virtual
        returns (bytes32)
    {
        bytes32 bh = L1_BLOCK.blockHash(_l1BlockNumber);
        require(bh != bytes32(0), "L2Base: failed to obtain blockhash");
        return RandaoLib.verifyHeaderAndGetRandao(bh, _headerRlpBytes);
    }

    /// @notice Check if the key-values being updated exceed the limit per block.
    function _checkUpdateLimit(uint256 _updateSize) internal virtual {
        uint256 blobsUpdated = updateState & MASK == block.number << 32 ? updateState & type(uint32).max : 0;
        require(blobsUpdated + _updateSize <= UPDATE_LIMIT, "L2Base: exceeds update rate limit");
        updateState = block.number << 32 | (blobsUpdated + _updateSize);
    }

    /// @notice Getter for UPDATE_LIMIT
    function getUpdateLimit() public view returns (uint256) {
        return UPDATE_LIMIT;
    }
}
