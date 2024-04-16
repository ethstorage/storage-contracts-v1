
const solc = require("solc");
const fs = require("fs");
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

async function changeContractBytecode(contractAddress, contractName, contractCode) {
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

    const output = JSON.parse(solc.compile(JSON.stringify(input)));
    const byteCode = "0x" + output.contracts[contractName][contractName].evm.deployedBytecode.object;
    await network.provider.send("hardhat_setCode", [
        contractAddress,
        byteCode,
    ]);
}

module.exports = {
    flattenContracts,
    changeContractBytecode
}
