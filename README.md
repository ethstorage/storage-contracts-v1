# EthStorage Decentralized Storage Contracts V1

## Style Guide
Smart contracts should be written according to this [STYLE_GUIDE.md](https://github.com/ethstorage/optimism/blob/develop/packages/contracts-bedrock/STYLE_GUIDE.md)

## How to verify the contract

- Implementation: npx hardhat verify --network sepolia <contract address>
- Proxy: npx hardhat verify --network sepolia --constructor-args arguments.js <contract address>
