// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MerkleLib.sol";
import "./BinaryRelated.sol";

contract DecentralizedKV {
    event Put(uint256 indexed kvIdx, uint256 indexed kvSize, bytes32 indexed dataHash);
    event Remove(uint256 indexed kvIdx, uint256 indexed lastKvIdx);

    uint256 public immutable storageCost; // Upfront storage cost (pre-dcf)
    // Discounted cash flow factor in seconds
    // E.g., 0.85 yearly discount in second = 0.9999999948465585 = 340282365167313208607671216367074279424 in Q128.128
    uint256 public immutable dcfFactor;
    uint256 public immutable startTime;
    uint256 public immutable maxKvSize;
    uint40 public lastKvIdx = 0; // number of entries in the store

    struct PhyAddr {
        /* Internal address seeking */
        uint40 kvIdx;
        /* BLOB size */
        uint24 kvSize;
        /* Commitment */
        bytes24 hash;
    }

    /* skey - PhyAddr */
    mapping(bytes32 => PhyAddr) internal kvMap;
    /* index - skey, reverse lookup */
    mapping(uint256 => bytes32) internal idxMap;

    constructor(uint256 _maxKvSize, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor) payable {
        startTime = _startTime;
        maxKvSize = _maxKvSize;
        storageCost = _storageCost;
        dcfFactor = _dcfFactor;
    }

    function pow(uint256 fp, uint256 n) internal pure returns (uint256) {
        return BinaryRelated.pow(fp, n);
    }

    // Evaluate payment from [t0, t1) seconds
    function _paymentInInterval(uint256 x, uint256 t0, uint256 t1) internal view returns (uint256) {
        return (x * (pow(dcfFactor, t0) - pow(dcfFactor, t1))) >> 128;
    }

    // Evaluate payment from [t0, \inf).
    function _paymentInf(uint256 x, uint256 t0) internal view returns (uint256) {
        return (x * pow(dcfFactor, t0)) >> 128;
    }

    // Evaluate payment from timestamp [fromTs, toTs)
    function _paymentIn(uint256 x, uint256 fromTs, uint256 toTs) internal view returns (uint256) {
        return _paymentInInterval(x, fromTs - startTime, toTs - startTime);
    }

    function _upfrontPayment(uint256 ts) internal view returns (uint256) {
        return _paymentInf(storageCost, ts - startTime);
    }

    // Evaluate the storage cost of a single put().
    function upfrontPayment() public view virtual returns (uint256) {
        return _upfrontPayment(block.timestamp);
    }

    function _prepareAppend() internal virtual {
        require(msg.value >= upfrontPayment(), "not enough payment");
    }

    function _getDataHash(uint256 blobIdx) internal virtual returns (bytes32) {}

    // Write a large value to KV store.  If the KV pair exists, overrides it.  Otherwise, will append the KV to the KV array.
    function put(bytes32 key, uint256 blobIdx, uint256 length) public payable {
        require(length <= maxKvSize, "data too large");
        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        PhyAddr memory paddr = kvMap[skey];

        if (paddr.hash == 0) {
            // append (require payment from sender)
            _prepareAppend();
            paddr.kvIdx = lastKvIdx;
            idxMap[paddr.kvIdx] = skey;
            lastKvIdx = lastKvIdx + 1;
        }
        paddr.kvSize = uint24(length);
        bytes32 dataHash = _getDataHash(blobIdx);
        paddr.hash = bytes24(dataHash);
        kvMap[skey] = paddr;

        emit Put(paddr.kvIdx, paddr.kvSize, dataHash);
    }

    // Return the size of the keyed value
    function size(bytes32 key) public view returns (uint256) {
        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        return kvMap[skey].kvSize;
    }

    // Exist
    function exist(bytes32 key) public view returns (bool) {
        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        return kvMap[skey].hash != 0;
    }

    // Return the keyed data given off and len.  This function can be only called in JSON-RPC context.
    function get(bytes32 key, uint256 off, uint256 len) public view returns (bytes memory) {
        // ES node will override this method to return actual data.
        require(false, "get() must be called on ES node");
    }

    // Remove an existing KV pair to a recipient.  Refund the cost accordingly.
    function removeTo(bytes32 key, address to) public {
        require(false, "removeTo() unimplemented");
    }

    // Remove an existing KV pair.  Refund the cost accordingly.
    function remove(bytes32 key) public {
        removeTo(key, msg.sender);
    }
}