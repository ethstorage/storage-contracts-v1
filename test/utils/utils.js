
const solc = require("solc");
const fs = require("fs");
const path = require("path");
const { network } = require("hardhat");
const { execSync } = require("child_process");

function flattenContracts(contractPath) {
    const cmd = `npx hardhat flatten ${contractPath}`;
    const tempFilePath = "temp_output.txt";
    execSync(`${cmd} > ${tempFilePath}`);

    const stdout = fs.readFileSync(tempFilePath, { encoding: "utf-8" });
    fs.unlinkSync(tempFilePath);
    return stdout;
}

async function getCompiler() {
    const solcPath = path.resolve("./test/utils/soljson-v0.8.24+commit.e11b9ed9.js");
    return solc.setupMethods(require(solcPath));
}

async function changeContractBytecode(contractAddress, contractName, contractCode, newVersion) {
    const sources = {};
    sources[contractName] = {content: contractCode};
    const input = {
        language: "Solidity",
        sources: sources,
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            },
            outputSelection: {
                "*": {
                    "*": ["*"],
                },
            },
        }
    };

    let output;
    if (newVersion) {
        output = JSON.parse(solc.compile(JSON.stringify(input)));
    } else {
        const compiler = await getCompiler();
        output = JSON.parse(compiler.compile(JSON.stringify(input)));
    }
    byteCode = "0x" + output.contracts[contractName][contractName].evm.deployedBytecode.object;
    await network.provider.send("hardhat_setCode", [
        contractAddress,
        byteCode,
    ]);
}

module.exports = {
    flattenContracts,
    changeContractBytecode
}
