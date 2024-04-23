// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


abstract contract EthStorageConstants {
    uint256 public constant maxKvSizeBits = 17; // maxKvSizeBits, 131072
    uint256 public constant shardSizeBits = 39; // shardSizeBits ~ 512G
    uint256 public constant shardEntryBits = shardSizeBits - maxKvSizeBits;
    uint256 public constant sampleLenBits = maxKvSizeBits - sampleSizeBits;
    uint256 public constant randomChecks = 2; // randomChecks
    uint256 public constant minimumDiff = 4718592000; // minimumDiff 5 * 3 * 3600 * 1024 * 1024 / 12 = 4718592000 for 5 replicas that can have 1M IOs in one epoch
    uint256 public constant cutoff = 7200; // cutoff = 2/3 * target internal (3 hours), 3 * 3600 * 2/3
    uint256 public constant diffAdjDivisor = 32; // diffAdjDivisor
    uint256 public constant treasuryShare = 100; // treasuryShare 10000 = 1.0, 100 means 1%
    uint256 public constant prepaidAmount = 3145728000000000000000; // prepaidAmount - 50% * 2^39 / 131072 * 1500000Gwei, it also means 3145 ETH for half of the shard

    // Upfront storage cost (pre-dcf)
    uint256 public constant storageCost = 1500000000000000; // storageCost - 1,500,000Gwei forever per blob - https://ethresear.ch/t/ethstorage-scaling-ethereum-storage-via-l2-and-da/14223/6#incentivization-for-storing-m-physical-replicas-1
    // Discounted cash flow factor in seconds
    // E.g., 0.85 yearly discount in second = 0.9999999948465585 = 340282365167313208607671216367074279424 in Q128.128
    uint256 public constant dcfFactor = 340282366367469178095360967382638002176; // it mean 0.95 for yearly discount
    uint256 public constant startTime = 1713782077;
    uint256 public constant maxKvSize = 1 << maxKvSizeBits; // 1 << maxKvSizeBits，131072

    uint256 public constant sampleSizeBits = 5; // 32 bytes per sample

    // maximum nonce per block
    uint256 public constant nonceLimit = 1048576; // nonceLimit 1024 * 1024 = 1M samples and finish sampling in 1.3s with IO rate 6144 MB/s: 4k * 2(random checks) / 6144 = 1.3s
}
