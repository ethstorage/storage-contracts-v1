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
    /// @notice Thrown when the blockhash cannot be obtained.
    error L2Base_FailedObtainBlockhash();

    /// @notice Thrown when the update rate limit is exceeded.
    error L2Base_ExceedsUpdateRateLimit();

    /// @notice The precompile contract address for L1Block.
    IL1Block internal constant L1_BLOCK = IL1Block(0x4200000000000000000000000000000000000015);

    /// @notice The mask to extract `blockLastUpdate`
    uint256 internal constant MASK = ~uint256(0) ^ type(uint32).max;

    /// @notice The rate limit to update blobs per block
    uint256 internal immutable UPDATE_LIMIT;

    /// @custom:storage-location erc7201:openzeppelin.storage.L2Base
    struct L2BaseStorage {
        /// @notice A slot to store both `blockLastUpdate` (left 224) and `blobsUpdated` (right 32)
        uint256 _updateState;
        /// @notice The address of the soul gas token.
        address _soulGasToken;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.L2Base")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant L2BaseStorageLocation = 0x4f2e75529ec26b25c2fdfe7928382000d9e4289cb7792c1db94ef3c9ffecd900;

    function _getL2BaseStorage() private pure returns (L2BaseStorage storage $) {
        assembly {
            $.slot := L2BaseStorageLocation
        }
    }

    /// @notice Constructs the L2Base contract.
    constructor(uint256 _updateLimit) {
        UPDATE_LIMIT = _updateLimit;
    }

    /// @notice Set the soul gas token address for the contract.
    function _setSoulGasToken(address _soulGasToken) internal {
        L2BaseStorage storage $ = _getL2BaseStorage();
        $._soulGasToken = _soulGasToken;
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

        if (bh == bytes32(0)) {
            revert L2Base_FailedObtainBlockhash();
        }

        return RandaoLib.verifyHeaderAndGetRandao(bh, _headerRlpBytes);
    }

    /// @notice Check if the key-values being updated exceed the limit per block.
    function _checkUpdateLimit(uint256 _updateSize) internal virtual {
        L2BaseStorage storage $ = _getL2BaseStorage();

        uint256 blobsUpdated = $._updateState & MASK == block.number << 32 ? $._updateState & type(uint32).max : 0;

        if (blobsUpdated + _updateSize > UPDATE_LIMIT) {
            revert L2Base_ExceedsUpdateRateLimit();
        }

        $._updateState = block.number << 32 | (blobsUpdated + _updateSize);
    }

    /// @notice Getter for UPDATE_LIMIT
    function getUpdateLimit() public view returns (uint256) {
        return UPDATE_LIMIT;
    }

    /// @notice Getter for the soul gas token address.
    function soulGasToken() public view returns (address) {
        L2BaseStorage storage $ = _getL2BaseStorage();
        return $._soulGasToken;
    }

    /// @notice Getter for update state.
    function updateState() internal view returns (uint256) {
        L2BaseStorage storage $ = _getL2BaseStorage();
        return $._updateState;
    }
}
