const snarkjs = require("snarkjs");

async function generateG16Proof(witness){
    const result = await snarkjs.groth16.fullProve(witness,"./test/lib/blob_poseidon.wasm", "./test/lib/blob_poseidon.zkey");
    // const result = await snarkjs.groth16.fullProve(witness,"./blob_poseidon.wasm", "./blob_poseidon.zkey");
    const inputs = result.publicSignals
    const proof = result.proof
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
        signals: [inputs[0],inputs[1],inputs[2]],
    }

    return [solProof,signals];
}

exports.generateG16Proof = generateG16Proof

//  ======================== local test ===============================
// let encodingKeyIn = "0x1234"
// let xIn = "0x20a35c046bbfefac7a49a93b3f078a4927390c265f05c6e1a014a1f5874b5a93"
// generateG16Proof({encodingKeyIn,xIn})