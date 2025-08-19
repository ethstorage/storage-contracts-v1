// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./libraries/BinaryRelated.sol";

/// @custom:upgradeable
/// @title DecentralizedKV
/// @notice The DecentralizedKV is a top base contract for the EthStorage contract. It provides the
///         basic key-value store functionalities.
contract DecentralizedKV is Initializable {
    /// @notice Thrown when the batch payment is not enough.
    error DecentralizedKV_NotEnoughBatchPayment();

    /// @notice Thrown when the data is too large.
    error DecentralizedKV_DataTooLarge();

    /// @notice Thrown when the data length is zero.
    error DecentralizedKV_DataLenZero();

    /// @notice Thrown when the data is beyond the range of kvSize.
    error DecentralizedKV_BeyondRangeOfKVSize();

    /// @notice Thrown when the get() is not called on ES node.
    error DecentralizedKV_GetMustBeCalledOnESNode();

    /// @notice Thrown when the data is not exist.
    error DecentralizedKV_DataNotExist();

    /// @notice The maximum value of optimization blob storage content. It can store 3068 bytes more data than standard blob.
    /// https://github.com/ethereum-optimism/optimism/blob/develop/op-service/eth/blob.go#L16
    uint256 internal constant MAX_OPTIMISM_BLOB_DATA_SIZE = (4 * 31 + 3) * 1024 - 4;

    /// @notice Upfront storage cost (pre-dcf)
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 internal immutable STORAGE_COST;

    /// @notice Discounted cash flow factor in seconds
    ///         E.g., 0.85 yearly discount in second = 0.9999999948465585 = 340282365167313208607671216367074279424 in Q128.128
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 internal immutable DCF_FACTOR;

    /// @notice The start time of the storage payment
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 internal immutable START_TIME;

    /// @notice Maximum size of a single key-value pair
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 internal immutable MAX_KV_SIZE;

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

    /// @custom:storage-location erc7201:openzeppelin.storage.DecentralizedKV
    struct DecentralizedKVStorage {
        /// @notice The number of entries in the store
        uint40 _kvEntryCount;
        /// @notice skey and PhyAddr mapping
        mapping(bytes32 => PhyAddr) _kvMap;
        /// @notice index and skey mapping, reverse lookup
        mapping(uint256 => bytes32) _idxMap;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.DecentralizedKV")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DecentralizedKVStorageLocation =
        0xdddbcfdf01968304fa73e5ba952efaf0203fd233c51e4f58b8a185ceb1c2a300;

    function _getDecentralizedKVStorage() private pure returns (DecentralizedKVStorage storage $) {
        assembly {
            $.slot := DecentralizedKVStorageLocation
        }
    }

    /// @notice Emitted when a key-value is removed.
    /// @param kvIdx        The removed key-value index.
    /// @param kvEntryCount The key-value entry count after removing the kvIdx.
    event Remove(uint256 indexed kvIdx, uint256 indexed kvEntryCount);

    /// @notice Constructs the DecentralizedKV contract. Initializes the immutables.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 _maxKvSize, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor) {
        MAX_KV_SIZE = _maxKvSize;
        START_TIME = _startTime;
        STORAGE_COST = _storageCost;
        DCF_FACTOR = _dcfFactor;
    }

    /// @notice Initializer.
    function __init_KV() internal onlyInitializing {
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        $._kvEntryCount = 0;
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

    /// @notice Checks while appending the key-value.
    function _checkAppend(uint256 _batchSize) internal virtual {
        if (msg.value < upfrontPayment() * _batchSize) {
            revert DecentralizedKV_NotEnoughBatchPayment();
        }
    }

    /// @notice Check if the key-values being updated exceed the limit per block (L2 only).
    function _checkUpdateLimit(uint256 _updateSize) internal virtual {}

    /// @notice Called by public putBlob and putBlobs methods.
    /// @param _keys       Keys of the data.
    /// @param _dataHashes Hashes of the data.
    /// @param _lengths    Lengths of the data.
    /// @return            The indices of the key-value.
    function _putBatchInternal(bytes32[] memory _keys, bytes32[] memory _dataHashes, uint256[] memory _lengths)
        internal
        returns (uint256[] memory)
    {
        uint256 keysLength = _keys.length;
        for (uint256 i = 0; i < keysLength; i++) {
            if (_lengths[i] > MAX_KV_SIZE) {
                revert DecentralizedKV_DataTooLarge();
            }
        }

        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();

        uint256[] memory res = new uint256[](keysLength);
        uint256 batchPaymentSize = 0;
        for (uint256 i = 0; i < keysLength; i++) {
            bytes32 skey = keccak256(abi.encode(msg.sender, _keys[i]));
            PhyAddr memory paddr = $._kvMap[skey];

            if (paddr.hash == 0) {
                // append (require payment from sender)
                batchPaymentSize++;
                paddr.kvIdx = $._kvEntryCount;
                $._idxMap[paddr.kvIdx] = skey;
                $._kvEntryCount = $._kvEntryCount + 1;
            }
            paddr.kvSize = uint24(_lengths[i]);
            paddr.hash = bytes24(_dataHashes[i]);
            $._kvMap[skey] = paddr;

            res[i] = paddr.kvIdx;
        }

        _checkAppend(batchPaymentSize);
        if (keysLength > batchPaymentSize) {
            _checkUpdateLimit(keysLength - batchPaymentSize);
        }

        return res;
    }

    /// @notice Return the size of the keyed value.
    function size(bytes32 _key) public view returns (uint256) {
        bytes32 skey = keccak256(abi.encode(msg.sender, _key));
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        return $._kvMap[skey].kvSize;
    }

    /// @notice Return the dataHash of the keyed value.
    function hash(bytes32 _key) public view returns (bytes24) {
        bytes32 skey = keccak256(abi.encode(msg.sender, _key));
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        return $._kvMap[skey].hash;
    }

    /// @notice Check if the key-value exists.
    function exist(bytes32 _key) public view returns (bool) {
        bytes32 skey = keccak256(abi.encode(msg.sender, _key));
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        return $._kvMap[skey].hash != 0;
    }

    // @notice Return the keyed data given off and len.  This function can be only called in JSON-RPC context of ES L2 node.
    /// @param _key        Key of the data.
    /// @param _decodeType Type of decoding.
    /// @param _off        Offset of the data.
    /// @param _len        Length of the data.
    /// @return            The data.
    function get(bytes32 _key, DecodeType _decodeType, uint256 _off, uint256 _len)
        public
        view
        virtual
        returns (bytes memory)
    {
        if (_len == 0) {
            revert DecentralizedKV_DataLenZero();
        }

        bytes32 skey = keccak256(abi.encode(msg.sender, _key));
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        PhyAddr memory paddr = $._kvMap[skey];

        if (paddr.hash == 0) {
            revert DecentralizedKV_DataNotExist();
        }

        if (_decodeType == DecodeType.OptimismCompact) {
            // kvSize is the actual data size that dApp contract stores
            if ((_off + _len > paddr.kvSize) || (_off + _len > MAX_OPTIMISM_BLOB_DATA_SIZE)) {
                revert DecentralizedKV_BeyondRangeOfKVSize();
            }
        } else if (_decodeType == DecodeType.PaddingPer31Bytes) {
            // kvSize is the actual data size that dApp contract stores
            if ((_off + _len > paddr.kvSize) || (_off + _len > MAX_KV_SIZE - 4096)) {
                revert DecentralizedKV_BeyondRangeOfKVSize();
            }
        } else {
            // maxKvSize is blob size
            if (_off + _len > MAX_KV_SIZE) {
                revert DecentralizedKV_BeyondRangeOfKVSize();
            }
        }

        bytes memory input = abi.encode(paddr.kvIdx, _decodeType, _off, _len, paddr.hash);
        bytes memory output = new bytes(_len);

        uint256 retSize = 0;

        assembly {
            if iszero(staticcall(not(0), 0x33301, add(input, 0x20), 0xa0, add(output, 0x20), _len)) { revert(0, 0) }
            retSize := returndatasize()
        }

        // If this function is called in a regular L1 node, there will no code in 0x33301,
        // and it will simply return immediately instead of revert
        if (retSize == 0) {
            revert DecentralizedKV_GetMustBeCalledOnESNode();
        }

        return output;
    }

    /// @notice Remove an existing KV pair with key `_key`.  Refund the cost accordingly to a recipient `_to`.
    function removeTo(bytes32, /* _key */ address /* _to */ ) public virtual {
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
        uint256 kvIndicesLength = _kvIndices.length;

        bytes32[] memory res = new bytes32[](kvIndicesLength);
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        for (uint256 i = 0; i < kvIndicesLength; i++) {
            PhyAddr memory paddr = $._kvMap[$._idxMap[_kvIndices[i]]];

            res[i] |= bytes32(uint256(_kvIndices[i])) << 216;
            res[i] |= bytes32(uint256(paddr.kvSize)) << 192;
            res[i] |= bytes32(paddr.hash) >> 64;
        }

        return res;
    }

    /// @notice Getter for kvEntryCount
    function kvEntryCount() public view returns (uint40) {
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        return $._kvEntryCount;
    }

    /// @notice Setter for kvEntryCount
    function _setKvEntryCount(uint40 _value) internal {
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        $._kvEntryCount = _value;
    }

    /// @notice Getter for kvMap
    function _kvMap(bytes32 _key) internal view returns (PhyAddr memory) {
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        return $._kvMap[_key];
    }

    /// @notice Setter for kvMap
    function _setKvMap(bytes32 _key, PhyAddr memory _value) internal {
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        $._kvMap[_key] = _value;
    }

    /// @notice Getter for idxMap
    function _idxMap(uint256 _kvIdx) internal view returns (bytes32) {
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        return $._idxMap[_kvIdx];
    }

    /// @notice Setter for idxMap
    function _setIdxMap(uint256 _kvIdx, bytes32 _value) internal {
        DecentralizedKVStorage storage $ = _getDecentralizedKVStorage();
        $._idxMap[_kvIdx] = _value;
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
