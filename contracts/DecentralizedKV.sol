// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./MerkleLib.sol";
import "./BinaryRelated.sol";
import "./EthStorageConstants.sol";

contract DecentralizedKV is OwnableUpgradeable, EthStorageConstants {
    event Remove(uint256 indexed kvIdx, uint256 indexed lastKvIdx);

    enum DecodeType {
        RawData,
        PaddingPer31Bytes
    }

    uint40 public lastKvIdx; // number of entries in the store

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

    function __init_KV(address _owner) public onlyInitializing {
        __Context_init();
        __Ownable_init(_owner);
        lastKvIdx = 0;
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
    function get(
        bytes32 key,
        DecodeType decodeType,
        uint256 off,
        uint256 len
    ) public view virtual returns (bytes memory) {
        require(len > 0, "data len should be non zero");

        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        PhyAddr memory paddr = kvMap[skey];
        require(paddr.hash != 0, "data not exist");
        if (decodeType == DecodeType.PaddingPer31Bytes) {
            // kvSize is the actual data size that dApp contract stores
            require((paddr.kvSize >= off + len) && (off + len <= maxKvSize - 4096), "beyond the range of kvSize");
        } else {
            // maxKvSize is blob size
            require(maxKvSize >= off + len, "beyond the range of maxKvSize");
        }
        bytes memory input = abi.encode(paddr.kvIdx, decodeType, off, len, paddr.hash);
        bytes memory output = new bytes(len);

        uint256 retSize = 0;

        assembly {
            if iszero(staticcall(not(0), 0x33301, add(input, 0x20), 0xa0, add(output, 0x20), len)) {
                revert(0, 0)
            }
            retSize := returndatasize()
        }

        // If this function is called in a regular L1 node, there will no code in 0x33301,
        // and it will simply return immediately instead of revert
        require(retSize > 0, "get() must be called on ES node");

        return output;
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
            PhyAddr memory paddr = kvMap[idxMap[kvIndices[i]]];

            res[i] |= bytes32(uint256(kvIndices[i])) << 216;
            res[i] |= bytes32(uint256(paddr.kvSize)) << 192;
            res[i] |= bytes32(paddr.hash) >> 64;
        }

        return res;
    }
}
