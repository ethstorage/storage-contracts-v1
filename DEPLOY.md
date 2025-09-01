
# Deploy and Upgrade

Since version `0.2.0`, you can use `openzeppelin-foundry-upgrades` to deploy and upgrade EthStorage contracts through shell scripts.
You can also prepare an upgrade for multi‑sig execution.

## Prerequisites

- Foundry installed (a stable version of `1.3.1-stable` or later): https://book.getfoundry.sh/getting-started/installation
- A `.env` file at repo root that modified from `.env.template`
---

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
./script/deploy.sh 22
```

After deployment, a deployment file is generated under the `deployments/` folder.
For example: `deployments/EthStorageContractM2L2_3335_v0.2.0-04b436a_deploy.txt`

**Sample deployment file:**

```bash
CONTRACT_NAME=EthStorageContractM2L2
CHAIN_ID=3335
DEPLOYER=0x471977571aD818379E2b6CC37792a5EaC85FdE22
PROXY=0x11e2a001E740A6cD5dCe7FEADAd6b221452aC182
ADMIN=0x962644257a0dA98fC3499531CC10222A258cEA60
IMPLEMENTATION=0x65c67cda963120CA3b71E9947fe465eD5825A869
OWNER=0x471977571aD818379E2b6CC37792a5EaC85FdE22
START_TIME=1755584956
VERSION=v0.2.0-04b436a
REFERENCE_BUILD_INFO_DIR=old-builds/build-info-v0.2.0-04b436a
REFERENCE_CONTRACT=build-info-v0.2.0-04b436a:EthStorageContractM2L2

DEPLOYED_AT=20250819_142757
```

This file serves as a reference for future upgrades. Specifically, `REFERENCE_BUILD_INFO_DIR` and `REFERENCE_CONTRACT` are used to get the build info of the previous version.

---

## Upgrade Contracts

To upgrade a deployed contract, pass the deployment file to the upgrade script:

```bash
./script/upgrade.sh <deployment_file>
```

**Example:**

```bash
./script/upgrade.sh deployments/EthStorageContractM2L2_3335_v0.2.0-04b436a_deploy.txt
```

After the upgrade, a new deployment file will also be created with the updated information.
---

## Prepare Upgrade

To prepare an upgrade for a contract:

```bash
./script/upgrade_prepare.sh <deployment_file>
```

**Example:**

```bash
./script/upgrade_prepare.sh deployments/EthStorageContractM2_31337_v0.2.0-108c728_deploy.txt
```

Note that the `prepareUpgrade` function the script calls does not upgrade the proxy directly; it only deploys a new implementation contract and returns the address of it. 
After that, you need to manually call the `updateAndCall` function on `ProxyAdmin` following a multi-sig workflow. 
---

## Additional Information

- Detailed logs are saved under `deployments/logs/` for all the scripts execution. 
- All the scripts automatically manage `old-builds` to archive build info, which is stored in `old-builds/build-info-{version}`, ensuring preparation for future upgrades using the same directory and name for the new version. 
- For details on how OpenZeppelin handles proxy upgrades, see the [OpenZeppelin Foundry Upgrades docs](https://docs.openzeppelin.com/upgrades-plugins/foundry-upgrades#upgrade_a_proxy_or_beacon).

