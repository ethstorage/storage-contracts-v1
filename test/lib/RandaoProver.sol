// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RLPWriter} from "./RLPWriter.sol";
import {ChainDataHelper} from "./ChainDataHelper.sol";

library RandaoProver {
    using RLPWriter for bytes;
    using RLPWriter for bytes[];

    /// @dev Generates the RLP-encoded block header for Randao verification.
    function generateRandaoProof(ChainDataHelper.BlockHeader memory blockHeader) internal pure returns (bytes memory) {
        bytes[] memory header = new bytes[](21);

        header[0] = RLPWriter.writeBytes(abi.encodePacked(blockHeader.parentHash));
        header[1] = RLPWriter.writeBytes(abi.encodePacked(blockHeader.sha3Uncles));
        header[2] = RLPWriter.writeAddress(blockHeader.miner);
        header[3] = RLPWriter.writeBytes(abi.encodePacked(blockHeader.stateRoot));
        header[4] = RLPWriter.writeBytes(abi.encodePacked(blockHeader.transactionsRoot));
        header[5] = RLPWriter.writeBytes(abi.encodePacked(blockHeader.receiptsRoot));
        header[6] = RLPWriter.writeBytes(blockHeader.logsBloom);
        header[7] = RLPWriter.writeUint(blockHeader.difficulty);
        header[8] = RLPWriter.writeUint(blockHeader.number);
        header[9] = RLPWriter.writeUint(blockHeader.gasLimit);
        header[10] = RLPWriter.writeUint(blockHeader.gasUsed);
        header[11] = RLPWriter.writeUint(blockHeader.timestamp);
        header[12] = RLPWriter.writeBytes(blockHeader.extraData);
        header[13] = RLPWriter.writeBytes(abi.encodePacked(blockHeader.mixHash));
        header[14] = RLPWriter.writeBytes(abi.encodePacked(blockHeader.nonce)); // "0x0000000000000000"
        header[15] = RLPWriter.writeUint(blockHeader.baseFeePerGas);
        header[16] = RLPWriter.writeBytes(abi.encodePacked(blockHeader.withdrawalsRoot));
        header[17] = RLPWriter.writeUint(blockHeader.blobGasUsed);
        header[18] = RLPWriter.writeUint(blockHeader.excessBlobGas);
        header[19] = RLPWriter.writeBytes(abi.encodePacked(blockHeader.parentBeaconBlockRoot));
        header[20] = RLPWriter.writeBytes(abi.encodePacked(blockHeader.requestsHash));

        return RLPWriter.writeList(header);
    }
}
