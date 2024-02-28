// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import "./EthStorageContract2.sol";

contract EthStorageCloneFactory {
    using ClonesWithImmutableArgs for address;

    struct Config {
        uint256 storageCost; // position 0
        uint256 dcfFactor;   // 1
        uint256 startTime;   // 2
        //_maxKvSize = 1 << _config.maxKvSizeBits

        uint256 maxKvSizeBits;  // 4
        uint256 shardSizeBits;  // 5
        uint256 shardEntryBits; // 6
        uint256 sampleLenBits;  // 7
        uint256 randomChecks;   // 8
        uint256 cutoff;         // 9
        uint256 diffAdjDivisor; // 10
        uint256 treasuryShare;  // 11
    }

    function createClone(EthStorageContract2 _ethStorageImpl, Config memory _cfg) public returns(address) {
        require(_cfg.shardSizeBits >= _cfg.maxKvSizeBits, "shardSize too small");
        require(_cfg.maxKvSizeBits >= _ethStorageImpl.sampleSizeBits(), "maxKvSize too small");
        require(_cfg.randomChecks > 0, "At least one checkpoint needed");

        bytes memory _data = abi.encodePacked(
            _cfg.storageCost, _cfg.dcfFactor, _cfg.startTime, 1 << _cfg.maxKvSizeBits,
            _cfg.maxKvSizeBits, _cfg.shardSizeBits, _cfg.shardEntryBits, _cfg.sampleLenBits,
            _cfg.randomChecks, _cfg.cutoff, _cfg.diffAdjDivisor, _cfg.treasuryShare
        );
        return address(_ethStorageImpl).clone(_data, 0); // 0, no pay
    }
}