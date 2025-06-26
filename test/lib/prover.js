const snarkjs = require("snarkjs");
const RLP = require("rlp");

require("dotenv").config();

async function generateG16Proof(witness) {
  const result = await snarkjs.groth16.fullProve(witness, process.env.G16_WASM_PATH, process.env.G16_ZKEY_PATH);
  const inputs = result.publicSignals;
  const proof = result.proof;
  const solProof = [
    [proof.pi_a[0], proof.pi_a[1]],
    [
      [proof.pi_b[0][1], proof.pi_b[0][0]],
      [proof.pi_b[1][1], proof.pi_b[1][0]],
    ],
    [proof.pi_c[0], proof.pi_c[1]],
  ];

  // the inputs format :
  // input[0] = encodingKey % modulusBn254;
  // input[1] = xBn254;
  // input[2] = mask;
  const signals = {
    signals: [inputs[0], inputs[1], inputs[2]],
  };

  return [solProof, signals];
}

async function generateRandaoProof(block) {
  const header = [
    block.parentHash,
    block.sha3Uncles,
    block.miner,
    block.stateRoot,
    block.transactionsRoot,
    block.receiptsRoot,
    block.logsBloom,
    BigInt(block.difficulty),
    BigInt(block.number),
    BigInt(block.gasLimit),
    BigInt(block.gasUsed),
    BigInt(block.timestamp),
    block.extraData,
    block.mixHash,
    "0x0000000000000000",
    BigInt(block.baseFeePerGas),
    block.withdrawalsRoot,
    BigInt(block.blobGasUsed),
    BigInt(block.excessBlobGas),
    block.parentBeaconBlockRoot,
    block.requestsHash,
  ];

  return RLP.encode(header);
}

exports.generateG16Proof = generateG16Proof;
exports.generateRandaoProof = generateRandaoProof;
