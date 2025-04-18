# EthStorage Storage Contract

## Overview
EthStorage is a modular and decentralized storage layer 2 (L2) that offers programmable key-value storage powered by data availability (DA).  It enables long-term DA solutions for Rollups and opens new possibilities for fully on-chain applications, such as games, social networks, and AI.

The EthStorage network consists of two main components:
 - **Storage contract on Ethereum L1**: Responsible for on-chain fee distribution and proof of storage verification.
 - **L2 storage network**: Composed of [es-nodes](https://github.com/ethstorage/es-node), responsible for off-chain data storage replicas and proof through continuous DA sampling.

You can find an overview of how it works [here](https://docs.ethstorage.io/readme/how-ethstorage-works).

Core functionalities of the storage contract:
 - Accept data uploads as 4844-BLOBs and store the BLOB data hash on-chain as part of a key-value store.
 - Verify the storage proof submitted by L2 storage providers against the on-chain BLOB hash to ensure they store the BLOB data off-chain.
 - Accept payments from users for data storage and continuously distribute those payments to the storage providers.

## Architecture
The storage contract inherits from several contracts, with each one in the inheritance chain implementing different functionalities. The inheritance hierarchy is as follows:
```
DecentralizedKV <- StorageContract <- EthStorageContract <- EthStorageContract2 <- EthStorageContractL2
```

### DecentralizedKV
DecentralizedKV is the top-level parent contract and provides the following core functionalities:
 - **Basic key-value store**: Users can upload data as 4844-BLOBs and retrieve it using the associated key. 
 - **Discounted cash flow algorithm**: It calculates upfront storage fees from users. More details on the storage fee model can be found in our [white paper](https://file.w3q.w3q-g.w3link.io/0x67d0481cc9c2e9dad2987e58a365aae977dcb8da/dynamic_data_sharding_0_1_6.pdf)

### StorageContract
StorageContract inherits from DecentralizedKV and focuses on two main features:
 - Multiple storage [shards](https://docs.ethstorage.io/readme/key-terms#shard).
 - **A fair and efficient on-chain fee distribution system** for storage providers:
    - **Fair**: Each replica is expected to receive 1/m of the fees, where m is the total number of physical replicas.
    - **Efficient communication**: The protocol cost is O(1) within a target interval (e.g., 6 hours).
More details on the fee distribution algorithm can be found in our [ESP report](https://docs.google.com/presentation/d/1zxbSTlIwe8ylifeS9bK0lKDRl5ALJfCm8lKCGbB98H0/edit#slide=id.g239a7f93be4_0_40)

### EthStorageContract
Each L2 storage provider has a unique replica encoded with the provider’s ID. Providers continuously perform random sampling, submitting qualified proofs to the contract.

EthStorageContract performs the following storage proof verifications submitted by L2 storage providers:
 - **Inclusive verification**: The contract verifies that the submitted sample data belongs to the stored off-chain BLOB.
 - **zk-SNARK-based encoding verification**: Each sample’s encoding is verified using zk-SNARKs. You can find the related circom [here](https://github.com/ethstorage/zk-decoder/blob/main/circom/circuits/blob_poseidon.circom). The number of random checks is flexible, but more checks increase on-chain verification gas costs.

### EthStorageContract2
To reduce gas costs, EthStorageContract2 performs a single verification, regardless of how many random sampling checks are required. The corresponding circom file is available [here](https://github.com/ethstorage/zk-decoder/blob/main/circom/circuits/blob_poseidon_2.circom)

### EthStorageContractL2
EthStorageContractL2 inherits from EthStorageContract2 and is designed for deployment on L2. While L1 BLOBs are currently inexpensive, Ethereum L1 execution costs remain high for many non-financial applications. Deploying the storage contract on L2 allows EthStorage to serve as a storage L3, offering lower storage costs for applications built on it. The L2 environment differs from L1, requiring two key modifications:
 - **Randomness source**: L2 doesn’t have a reliable random generator like L1’s RANDAO. To address this, L1 [blockhash](https://github.com/ethstorage/optimism/blob/cd66e3ab6fab1b736d07677e80d5b3f3e1401228/packages/contracts-bedrock/src/L2/L1Block.sol#L182) is bridged to L2 for verification.
 - **Rate limiting**: With lower execution costs, it becomes feasible to perform numerous key-value updates at a reasonable cost. To prevent potential DoS attacks, rate limiting is implemented.

## Setup
 - Install foundry by following the [link](https://book.getfoundry.sh/getting-started/installation)
 - npm run install:all
 - npm run test


## Style Guide
Smart contracts should be written according to this [STYLE_GUIDE.md](https://github.com/ethstorage/optimism/blob/develop/packages/contracts-bedrock/STYLE_GUIDE.md)

## How to verify the contract

For QuarkChain Layer 2 which is using the blockscout, we will use the following command to verify:
- Implementation: npx hardhat verify --network qkc_testnet <impl-addr> --constructor-args args.js
- Proxy: npx hardhat verify --force --network qkc_testnet <proxy-addr> <impl-addr> <owner-addr> <data>
