// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./libraries/MerkleLib.sol";
import "./libraries/BinaryRelated.sol";

/// @custom:upgradeable
/// @title DecentralizedKV
/// @notice The DecentralizedKV is a top base contract for the EthStorage contract. It provides the
///         basic key-value store functionalities.
contract DecentralizedKV is OwnableUpgradeable {
    /// @notice Represents the metadata of the key-value .
    /// @custom:field kvIdx  Internal address seeking.
    /// @custom:field kvSize BLOB size.
    /// @custom:field hash   Commitment.
    struct PhyAddr {
        uint40 kvIdx;
        uint24 kvSize;
        bytes24 hash;
    }

    /// @notice Enum representing different decoding types when getting key-value.
    /// @custom:field RawData           Don't do any decoding.
    /// @custom:field PaddingPer31Bytes Will remove the padding byte every 31 bytes.
    /// @custom:field OptimismCompact   Use Op blob encoding format.
    enum DecodeType {
        RawData,
        PaddingPer31Bytes,
        OptimismCompact
    }

    /// @notice The maximum value of optimization blob storage content. It can store 3068 bytes more data than standard blob.
    /// https://github.com/ethereum-optimism/optimism/blob/develop/op-service/eth/blob.go#L16
    uint256 internal constant MAX_OPTIMISM_BLOB_DATA_SIZE = (4 * 31 + 3) * 1024 - 4;

    /// @notice Upfront storage cost (pre-dcf)
    uint256 internal immutable STORAGE_COST;

    /// @notice Discounted cash flow factor in seconds
    ///         E.g., 0.85 yearly discount in second = 0.9999999948465585 = 340282365167313208607671216367074279424 in Q128.128
    uint256 internal immutable DCF_FACTOR;

    /// @notice The start time of the storage payment
    uint256 internal immutable START_TIME;

    /// @notice Maximum size of a single key-value pair
    uint256 internal immutable MAX_KV_SIZE;

    /// @custom:legacy
    /// @custom:spacer storageCost, dcfFactor, startTime, maxKvSize
    /// @notice Spacer for backwards compatibility.
    uint256[4] private kvSpacers;

    /// @notice The number of entries in the store
    uint40 public kvEntryCount;

    /// @notice skey and PhyAddr mapping
    mapping(bytes32 => PhyAddr) internal kvMap;

    /// @notice index and skey mapping, reverse lookup
    mapping(uint256 => bytes32) internal idxMap;

    /// @notice Emitted when a key-value is removed.
    /// @param kvIdx        The removed key-value index.
    /// @param kvEntryCount The key-value entry count after removing the kvIdx.
    event Remove(uint256 indexed kvIdx, uint256 indexed kvEntryCount);

    // TODO: Reserve extra slots (to a total of 50?) in the storage layout for future upgrades

    /// @notice Constructs the DecentralizedKV contract. Initializes the immutables.
    constructor(uint256 _maxKvSize, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor) {
        MAX_KV_SIZE = _maxKvSize;
        START_TIME = _startTime;
        STORAGE_COST = _storageCost;
        DCF_FACTOR = _dcfFactor;
    }

    /// @notice Initializer.
    /// @param _owner The contract owner.
    function __init_KV(address _owner) internal onlyInitializing {
        __Context_init();
        __Ownable_init(_owner);
        kvEntryCount = 0;
    }

    /// @notice Pow function in Q128.
    function _pow(uint256 _fp, uint256 _n) internal pure returns (uint256) {
        return BinaryRelated.pow(_fp, _n);
    }

    /// @notice Evaluate payment from [t0, t1) seconds
    function _paymentInInterval(uint256 _x, uint256 _t0, uint256 _t1) internal view returns (uint256) {
        return (_x * (_pow(DCF_FACTOR, _t0) - _pow(DCF_FACTOR, _t1))) >> 128;
    }

    /// @notice Evaluate payment from [t0, \inf).
    function _paymentInf(uint256 _x, uint256 _t0) internal view returns (uint256) {
        return (_x * _pow(DCF_FACTOR, _t0)) >> 128;
    }

    /// @notice Evaluate payment from timestamp [fromTs, toTs)
    function _paymentIn(uint256 _x, uint256 _fromTs, uint256 _toTs) internal view returns (uint256) {
        return _paymentInInterval(_x, _fromTs - START_TIME, _toTs - START_TIME);
    }

    /// @notice Evaluate payment given the timestamp.
    function _upfrontPayment(uint256 _ts) internal view returns (uint256) {
        return _paymentInf(STORAGE_COST, _ts - START_TIME);
    }

    /// @notice Evaluate the storage cost of a single put().
    function upfrontPayment() public view virtual returns (uint256) {
        return _upfrontPayment(block.timestamp);
    }

    /// @notice Checks before appending the key-value.
    function _prepareAppend() internal virtual {
        require(msg.value >= upfrontPayment(), "DecentralizedKV: not enough payment");
    }

    /// @notice Called by public put method.
    /// @param _key      Key of the data.
    /// @param _dataHash Hash of the data.
    /// @param _length   Length of the data.
    /// @return          The index of the key-value.
    function _putInternal(bytes32 _key, bytes32 _dataHash, uint256 _length) internal returns (uint256) {
        require(_length <= MAX_KV_SIZE, "DecentralizedKV: data too large");
        bytes32 skey = keccak256(abi.encode(msg.sender, _key));
        PhyAddr memory paddr = kvMap[skey];

        if (paddr.hash == 0) {
            // append (require payment from sender)
            _prepareAppend();
            paddr.kvIdx = kvEntryCount;
            idxMap[paddr.kvIdx] = skey;
            kvEntryCount = kvEntryCount + 1;
        }
        paddr.kvSize = uint24(_length);
        paddr.hash = bytes24(_dataHash);
        kvMap[skey] = paddr;

        return paddr.kvIdx;
    }

    /// @notice Return the size of the keyed value.
    function size(bytes32 _key) public view returns (uint256) {
        bytes32 skey = keccak256(abi.encode(msg.sender, _key));
        return kvMap[skey].kvSize;
    }

    /// @notice Return the dataHash of the keyed value.
    function hash(bytes32 _key) public view returns (bytes24) {
        bytes32 skey = keccak256(abi.encode(msg.sender, _key));
        return kvMap[skey].hash;
    }

    /// @notice Check if the key-value exists.
    function exist(bytes32 _key) public view returns (bool) {
        bytes32 skey = keccak256(abi.encode(msg.sender, _key));
        return kvMap[skey].hash != 0;
    }

    // @notice Return the keyed data given off and len.  This function can be only called in JSON-RPC context of ES L2 node.
    /// @param _key        Key of the data.
    /// @param _decodeType Type of decoding.
    /// @param _off        Offset of the data.
    /// @param _len        Length of the data.
    /// @return            The data.
    function get(
        bytes32 _key,
        DecodeType _decodeType,
        uint256 _off,
        uint256 _len
    ) public view virtual returns (bytes memory) {
        require(_len > 0, "DecentralizedKV: data len should be non zero");

        bytes32 skey = keccak256(abi.encode(msg.sender, _key));
        PhyAddr memory paddr = kvMap[skey];
        require(paddr.hash != 0, "DecentralizedKV: data not exist");
        if (_decodeType == DecodeType.OptimismCompact) {
            // kvSize is the actual data size that dApp contract stores
            // (4*31+3)*1024 - 4 is the maximum value of optimization blob storage content. It can store 3068 bytes more data than standard blob.
            // https://github.com/ethereum-optimism/optimism/blob/develop/op-service/eth/blob.go#L16
            require(
                (paddr.kvSize >= _off + _len) && (_off + _len <= MAX_OPTIMISM_BLOB_DATA_SIZE),
                "DecentralizedKV: beyond the range of kvSize"
            );
        } else if (_decodeType == DecodeType.PaddingPer31Bytes) {
            // kvSize is the actual data size that dApp contract stores
            require(
                (paddr.kvSize >= _off + _len) && (_off + _len <= MAX_KV_SIZE - 4096),
                "DecentralizedKV: beyond the range of kvSize"
            );
        } else {
            // maxKvSize is blob size
            require(MAX_KV_SIZE >= _off + _len, "DecentralizedKV: beyond the range of maxKvSize");
        }

        bytes memory input = abi.encode(paddr.kvIdx, _decodeType, _off, _len, paddr.hash);
        bytes memory output = new bytes(_len);

        uint256 retSize = 0;

        assembly {
            if iszero(staticcall(not(0), 0x33301, add(input, 0x20), 0xa0, add(output, 0x20), _len)) {
                revert(0, 0)
            }
            retSize := returndatasize()
        }

        // If this function is called in a regular L1 node, there will no code in 0x33301,
        // and it will simply return immediately instead of revert
        require(retSize > 0, "DecentralizedKV: get() must be called on ES node");

        return output;
    }

    /// @notice Remove an existing KV pair to a recipient.  Refund the cost accordingly.
    /// @param _key Key of the data.
    /// @param _to  The recipient address.
    function removeTo(bytes32 _key, address _to) public virtual {
        revert("DecentralizedKV: removeTo() unimplemented");
    }

    /// @notice Remove an existing KV pair.  Refund the cost accordingly.
    /// @param _key Key of the data.
    function remove(bytes32 _key) public {
        removeTo(_key, msg.sender);
    }

    /// @notice Get the metadata of the key-value.
    /// @param _kvIndices The indices of the key-value.
    /// @return The metadatas of the key-value.
    function getKvMetas(uint256[] memory _kvIndices) public view virtual returns (bytes32[] memory) {
        bytes32[] memory res = new bytes32[](_kvIndices.length);

        for (uint256 i = 0; i < _kvIndices.length; i++) {
            PhyAddr memory paddr = kvMap[idxMap[_kvIndices[i]]];

            res[i] |= bytes32(uint256(_kvIndices[i])) << 216;
            res[i] |= bytes32(uint256(paddr.kvSize)) << 192;
            res[i] |= bytes32(paddr.hash) >> 64;
        }

        return res;
    }

    /// @notice This is for compatibility with earlier versions and can be removed in the future.
    function lastKvIdx() public view returns (uint40) {
        return kvEntryCount;
    }

    /// @notice Getter for STORAGE_COST
    function storageCost() public view returns (uint256) {
        return STORAGE_COST;
    }

    /// @notice Getter for DCF_FACTOR
    function dcfFactor() public view returns (uint256) {
        return DCF_FACTOR;
    }

    /// @notice Getter for START_TIME
    function startTime() public view returns (uint256) {
        return START_TIME;
    }

    /// @notice Getter for MAX_KV_SIZE
    function maxKvSize() public view returns (uint256) {
        return MAX_KV_SIZE;
    }
}
