
# Deploy and Upgrade

Since version `0.2.0`, you can use `openzeppelin-foundry-upgrades` to **deploy** and **upgrade** EthStorage contracts through simple scripts. 

## Deploy Contracts

Run the deployment script with the contract type you want to deploy:

```bash
./script/deploy.sh <contract_type>
```

**Supported contract types:**

```
11 - EthStorageContractM1
12 - EthStorageContractM1L2
21 - EthStorageContractM2
22 - EthStorageContractM2L2
```

**Example:**

```bash
./script/deploy.sh 21
```

After deployment, a deployment record is generated under the `deployments/` folder.
For example: `deployments/EthStorageContractM2_31337_0.2.0.txt`

**Sample deployment file:**

```
CONTRACT_NAME=EthStorageContractM2
CHAIN_ID=31337
DEPLOYER=0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65
PROXY=0x93C7a6D00849c44Ef3E92E95DCEFfccd447909Ae
ADMIN=0xdA510e6c845e9bd3ee023d660f353b0aEf7b7dC0
IMPLEMENTATION=0xA7918D253764E42d60C3ce2010a34d5a1e7C1398
OWNER=0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65
START_TIME=1755244097
VERSION=0.2.0
REFERENCE_BUILD_INFO_DIR=old-builds/build-info-v0.2.0
REFERENCE_CONTRACT=build-info-v0.2.0:EthStorageContractM2
DEPLOYED_AT=20250815_155610
```

This file serves as a reference for future upgrades.

---

## Upgrade Contracts

To upgrade a deployed contract, pass the deployment file to the upgrade script:

```bash
./script/upgrade.sh <deployment_file>
```

**Example:**

```bash
./script/upgrade.sh deployments/EthStorageContractM2_31337_0.2.0.txt
```

After the upgrade, a new deployment file will be created with the updated information.

---

## Additional Information

- During the upgrade, `REFERENCE_BUILD_INFO_DIR` and `REFERENCE_CONTRACT` (from the deployment file) are used to get the build info of the **previous version**.
- Both deployment and upgrade steps automatically manage `old-builds` to archive build info, which is stored in `old-builds/build-info-{version}`, ensuring preparation for future upgrades.

For details on how OpenZeppelin handles proxy upgrades with the option of using the same directory and name for the new version, see the [OpenZeppelin Foundry Upgrades docs](https://docs.openzeppelin.com/upgrades-plugins/foundry-upgrades#upgrade_a_proxy_or_beacon).
