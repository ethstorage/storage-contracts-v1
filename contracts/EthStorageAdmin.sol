// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract EthStorageAdmin is ProxyAdmin {

    constructor(address initialOwner) ProxyAdmin(initialOwner) {}

}
