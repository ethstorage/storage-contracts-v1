// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./BinaryRelated.sol";

contract test {
    function test1() public pure returns (uint256) {
        uint256 x = BinaryRelated.pow(340282365167313208607671216367074279424, 0);
        return 1 << 128;
    }
}
