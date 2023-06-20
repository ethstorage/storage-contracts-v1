// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library MiningLib {
    struct MiningInfo {
        uint256 lastMineTime;
        uint256 difficulty;
        uint256 blockMined;
    }

    event MinedBlock(uint256 lastMineTime, uint256 difficulty, uint256 blockMined);

    function expectedDiff(
        MiningInfo storage info,
        uint256 mineTime,
        uint256 targetIntervalSec,
        uint256 cutoff,
        uint256 diffAdjDivisor,
        uint256 minDiff
    ) internal view returns (uint256) {
        // Check if the diff matches
        // Use modified ETH diff algorithm
        uint256 interval = mineTime - info.lastMineTime;
        uint256 diff = info.difficulty;
        if (interval < targetIntervalSec) {
            diff = diff + ((1 - interval / cutoff) * diff) / diffAdjDivisor;
            if (diff < minDiff) {
                diff = minDiff;
            }
        } else {
            uint256 dec = ((interval / cutoff - 1) * diff) / diffAdjDivisor;
            if (dec + minDiff > diff) {
                diff = minDiff;
            } else {
                diff = diff - dec;
            }
        }
        return diff;
    }

    function update(MiningInfo storage info, uint256 mineTime, uint256 diff) internal {
        // A block is mined!
        info.blockMined = info.blockMined + 1;
        info.difficulty = diff;
        info.lastMineTime = mineTime;
        emit MinedBlock(mineTime, diff, info.blockMined);
    }
}
