// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MerkleLib.sol";
import "./BinaryRelated.sol";

contract DecentralizedKV {
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

    function _putInternal(bytes32 key, bytes32 dataHash, uint256 length) internal returns (uint256) {
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
        paddr.hash = bytes24(dataHash);
        kvMap[skey] = paddr;

        return paddr.kvIdx;
    }

    // Return the size of the keyed value
    function size(bytes32 key) public view returns (uint256) {
        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        return kvMap[skey].kvSize;
    }

    // Return the dataHash of the keyed value
    function hash(bytes32 key) public view returns (bytes24) {
        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        return kvMap[skey].hash;
    }

    // Exist
    function exist(bytes32 key) public view returns (bool) {
        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        return kvMap[skey].hash != 0;
    }

    // Return the keyed data given off and len.  This function can be only called in JSON-RPC context of ES L2 node.
    function get(bytes32 key, uint256 off, uint256 len) public view virtual returns (bytes memory result) {
        require(len > 0, "data len should be non zero");

        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        PhyAddr memory paddr = kvMap[skey];
        require(paddr.hash != 0, "data not exist");
        require(paddr.kvSize >= off + len, "beyond the range of kvSize");
        bytes memory input = abi.encode(paddr.kvIdx, off, len, paddr.hash);

        uint256 retSize = 0;

        assembly {
            if iszero(staticcall(not(0), 0x33301, add(input, 0x20), 0x80, 0x0, len)) {
                revert(0, 0)
            }
            retSize := returndatasize()
        }

        // If this function is called in a regular L1 node, there will no code in 0x33301,
        // and it will simply return immediately instead of revert
        require(retSize > 0, "get() must be called on ES node");

        assembly {
            // Allocate memory for the result
            result := mload(0x40)
            mstore(result, returndatasize())

            // Update free memory pointer
            mstore(0x40, add(result, add(returndatasize(), 0x20)))

            // Copy the result to the allocated memory
            returndatacopy(add(result, 0x20), 0, returndatasize())
        }
    }

    // Remove an existing KV pair to a recipient.  Refund the cost accordingly.
    function removeTo(bytes32 key, address to) public virtual {
        require(false, "removeTo() unimplemented");
    }

    // Remove an existing KV pair.  Refund the cost accordingly.
    function remove(bytes32 key) public {
        removeTo(key, msg.sender);
    }

    function getKvMetas(uint256[] memory kvIndices) public view virtual returns (bytes32[] memory) {
        bytes32[] memory res = new bytes32[](kvIndices.length);

        for (uint256 i = 0; i < kvIndices.length; i++) {
            PhyAddr memory paddr = kvMap[idxMap[i]];

            res[i] |= bytes32(uint256(paddr.kvIdx)) << 216;
            res[i] |= bytes32(uint256(paddr.kvSize)) << 192;
            res[i] |= bytes32(paddr.hash) >> 64;
        }

        return res;
    }
}
