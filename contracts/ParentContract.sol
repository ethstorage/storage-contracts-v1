// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.0;

contract ParentContract {
    uint256 public constant storageCost = 1500000000000000; // storageCost - 1,500,000Gwei forever per blob - https://ethresear.ch/t/ethstorage-scaling-ethereum-storage-via-l2-and-da/14223/6#incentivization-for-storing-m-physical-replicas-1
    // Discounted cash flow factor in seconds
    // E.g., 0.85 yearly discount in second = 0.9999999948465585 = 340282365167313208607671216367074279424 in Q128.128
    uint256 public constant dcfFactor = 340282366367469178095360967382638002176; // it mean 0.95 for yearly discount
    uint256 public constant maxKvSize = 131072; // 1 << maxKvSizeBits，1 << 17 is 131072


}
