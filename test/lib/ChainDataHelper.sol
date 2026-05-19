// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, stdJson} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract ChainDataHelper is Test {
    using stdJson for string;

    struct BlockHeader {
        bytes32 parentHash;
        bytes32 sha3Uncles;
        address miner;
        bytes32 stateRoot;
        bytes32 transactionsRoot;
        bytes32 receiptsRoot;
        bytes logsBloom;
        uint256 difficulty;
        uint256 number;
        uint256 gasLimit;
        uint256 gasUsed;
        uint256 timestamp;
        bytes extraData;
        bytes32 mixHash;
        uint64 nonce;
        uint256 baseFeePerGas;
        bytes32 withdrawalsRoot;
        uint256 blobGasUsed;
        uint256 excessBlobGas;
        bytes32 parentBeaconBlockRoot;
        bytes32 requestsHash;
    }

    /// @dev Fetches the latest block header from an L1 node using `cast rpc`.
    function fetchLatestBlockHeader() internal returns (ChainDataHelper.BlockHeader memory header, bytes32 blockHash) {
        string[] memory cmd = new string[](7);
        cmd[0] = "cast";
        cmd[1] = "rpc";
        cmd[2] = "--rpc-url";
        cmd[3] = vm.envString("RPC_URL_L1");
        cmd[4] = "eth_getBlockByNumber";
        cmd[5] = "latest";
        cmd[6] = "false";

        Vm.FfiResult memory res = vm.tryFfi(cmd);
        require(res.exitCode == 0, string.concat("cast rpc failed: ", string(res.stderr)));
        bytes memory stdout = res.stdout;
        require(stdout.length != 0, "cast rpc returned empty stdout");

        string memory json = string(stdout);

        blockHash = json.readBytes32(".hash");
        header.parentHash = json.readBytes32(".parentHash");
        header.sha3Uncles = json.readBytes32(".sha3Uncles");
        header.miner = json.readAddress(".miner");
        header.stateRoot = json.readBytes32(".stateRoot");
        header.transactionsRoot = json.readBytes32(".transactionsRoot");
        header.receiptsRoot = json.readBytes32(".receiptsRoot");
        header.logsBloom = json.readBytes(".logsBloom");
        header.difficulty = json.readUint(".difficulty");
        header.number = json.readUint(".number");
        header.gasLimit = json.readUint(".gasLimit");
        header.gasUsed = json.readUint(".gasUsed");
        header.timestamp = json.readUint(".timestamp");
        header.extraData = json.readBytes(".extraData");
        header.mixHash = json.readBytes32(".mixHash");
        header.nonce = uint64(json.readUint(".nonce"));
        header.baseFeePerGas = json.readUint(".baseFeePerGas");
        header.withdrawalsRoot = json.readBytes32(".withdrawalsRoot");
        header.blobGasUsed = json.readUintOr(".blobGasUsed", 0);
        header.excessBlobGas = json.readUintOr(".excessBlobGas", 0);
        header.parentBeaconBlockRoot = json.readBytes32Or(".parentBeaconBlockRoot", bytes32(0));
        header.requestsHash = json.readBytes32Or(".requestsHash", bytes32(0));

        return (header, blockHash);
    }
}
