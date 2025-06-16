// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract EthStorageUpgradeableProxy is TransparentUpgradeableProxy {
    constructor(address _logic, address initialOwner, bytes memory _data)
        payable
        TransparentUpgradeableProxy(_logic, initialOwner, _data)
    {}

    receive() external payable virtual {}

    function admin() public view virtual returns (address) {
        return ERC1967Utils.getAdmin();
    }

    function implementation() public view virtual returns (address) {
        return ERC1967Utils.getImplementation();
    }
}
