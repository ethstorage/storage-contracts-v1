// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title MiningLib
/// @notice Handles mining difficulty calculation and mining info update
library MiningLib {
    /// @notice MiningInfo represents the mining information of a shard
    /// @custom:field lastMineTime The last time a block was mined
    /// @custom:field difficulty The current difficulty of the shard
    /// @custom:field blockMined The number of blocks mined
    struct MiningInfo {
        uint256 lastMineTime;
        uint256 difficulty;
        uint256 blockMined;
    }

    /// @notice Calculate the expected difficulty of the next block
    /// @param _info The mining information of the shard
    /// @param _mineTime The mined time of the next block
    /// @param _cutoff Cutoff time for difficulty adjustment
    /// @param _diffAdjDivisor The divisor to adjust the difficulty
    /// @param _minDiff The minimum difficulty
    /// @return The expected difficulty of the next block
    function expectedDiff(
        MiningInfo storage _info,
        uint256 _mineTime,
        uint256 _cutoff,
        uint256 _diffAdjDivisor,
        uint256 _minDiff
    ) internal view returns (uint256) {
        // Check if the diff matches
        // Use modified ETH diff algorithm
        uint256 interval = _mineTime - _info.lastMineTime;
        uint256 diff = _info.difficulty;
        if (interval < _cutoff) {
            diff = diff + ((1 - interval / _cutoff) * diff) / _diffAdjDivisor;
            if (diff < _minDiff) {
                diff = _minDiff;
            }
        } else {
            uint256 dec = ((interval / _cutoff - 1) * diff) / _diffAdjDivisor;
            if (dec + _minDiff > diff) {
                diff = _minDiff;
            } else {
                diff = diff - dec;
            }
        }
        return diff;
    }

    /// @notice Update the mining information of the shard
    /// @param _info The mining information of the shard
    /// @param _mineTime The mined time of the next block
    /// @param _diff The difficulty of the next block
    function update(MiningInfo storage _info, uint256 _mineTime, uint256 _diff) internal {
        // A block is mined!
        _info.blockMined = _info.blockMined + 1;
        _info.difficulty = _diff;
        _info.lastMineTime = _mineTime;
    }
}
