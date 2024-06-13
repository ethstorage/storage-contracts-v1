// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DecentralizedKV.sol";

contract TestDecentralizedKV is DecentralizedKV {
    uint256 public currentTimestamp;

    mapping(uint256 => bytes) internal dataMap;

    constructor(
        uint256 _maxKvSize,
        uint256 _startTime,
        uint256 _storageCost,
        uint256 _dcfFactor
    ) DecentralizedKV(_maxKvSize, _startTime, _storageCost, _dcfFactor) {}

    function initialize(address owner) public initializer {
        __init_KV(owner);
    }

    function setTimestamp(uint256 ts) public {
        require(ts > currentTimestamp, "ts");
        currentTimestamp = ts;
    }

    function upfrontPayment() public view override returns (uint256) {
        return _upfrontPayment(currentTimestamp);
    }

    function put(bytes32 key, bytes memory data) public payable {
        bytes32 dataHash = keccak256(data);
        uint256 kvIdx = _putInternal(key, dataHash, data.length);
        dataMap[kvIdx] = data;
    }

    function get(
        bytes32 key,
        DecodeType decodeType,
        uint256 off,
        uint256 len
    ) public view override returns (bytes memory) {
        if (len == 0) {
            return new bytes(0);
        }

        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        PhyAddr memory paddr = kvMap[skey];
        if (off >= paddr.kvSize) {
            return new bytes(0);
        }

        if (len + off > paddr.kvSize) {
            len = paddr.kvSize - off;
        }

        bytes memory data = dataMap[paddr.kvIdx];
        bytes memory ret = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            ret[i] = data[i + off];
        }
        return ret;
    }

    // Remove an existing KV pair to a recipient.  Refund the cost accordingly.
    function removeTo(bytes32 key, address to) public override {
        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        PhyAddr memory paddr = kvMap[skey];
        uint40 kvIdx = paddr.kvIdx;

        require(paddr.hash != 0, "kv not exist");

        // clear kv data
        kvMap[skey] = PhyAddr({kvIdx: 0, kvSize: 0, hash: 0});

        // move last kv to current kv
        bytes32 lastSkey = idxMap[lastKvIdx - 1];
        idxMap[kvIdx] = lastSkey;
        kvMap[lastSkey].kvIdx = kvIdx;

        // remove the last Kv
        idxMap[lastKvIdx - 1] = 0x0;
        lastKvIdx = lastKvIdx - 1;

        dataMap[kvIdx] = dataMap[lastKvIdx];
        delete dataMap[lastKvIdx];

        payable(to).transfer(upfrontPayment());
    }
}
