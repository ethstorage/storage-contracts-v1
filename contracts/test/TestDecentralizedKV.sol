// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../DecentralizedKV.sol";

contract TestDecentralizedKV is DecentralizedKV {
    uint256 public currentTimestamp;

    mapping(uint256 => bytes) internal dataMap;

    constructor(uint256 _maxKvSize, uint256 _startTime, uint256 _storageCost, uint256 _dcfFactor)
        DecentralizedKV(_maxKvSize, _startTime, _storageCost, _dcfFactor)
    {}

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

        bytes32[] memory keys = new bytes32[](1);
        keys[0] = key;
        bytes32[] memory dataHashes = new bytes32[](1);
        dataHashes[0] = dataHash;
        uint256[] memory lengths = new uint256[](1);
        lengths[0] = data.length;

        uint256[] memory kvIndices = _putBatchInternal(keys, dataHashes, lengths);
        dataMap[kvIndices[0]] = data;
    }

    function get(bytes32 key, DecodeType, /* decodeType */ uint256 off, uint256 len)
        public
        view
        override
        returns (bytes memory)
    {
        if (len == 0) {
            return new bytes(0);
        }

        bytes32 skey = keccak256(abi.encode(msg.sender, key));
        PhyAddr memory paddr = _kvMap(skey);
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
        PhyAddr memory paddr = _kvMap(skey);
        uint40 kvIdx = paddr.kvIdx;

        require(paddr.hash != 0, "kv not exist");

        // clear kv data
        _setKvMap(skey, PhyAddr({kvIdx: 0, kvSize: 0, hash: 0}));

        // move last kv to current kv
        bytes32 lastSkey = _idxMap(kvEntryCount() - 1);
        _setIdxMap(kvIdx, lastSkey);

        PhyAddr memory lastValue = _kvMap(lastSkey);
        lastValue.kvIdx = kvIdx;
        _setKvMap(lastSkey, lastValue);

        // remove the last Kv
        _setIdxMap(kvEntryCount() - 1, 0x0);
        _setKvEntryCount(kvEntryCount() - 1);

        dataMap[kvIdx] = dataMap[kvEntryCount()];
        delete dataMap[kvEntryCount()];

        payable(to).transfer(upfrontPayment());
    }
}
