require("dotenv").config();
const fs = require('fs');

require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");
require("hardhat-gas-reporter");
require("solidity-coverage");

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

const temp_time = "temp_time.txt";

task("times", "Change startTime", async (taskArgs, hre) => {
  const startTime = "1713782077";
  const newStartTime = Math.floor(new Date().getTime() / 1000);

  // replace
  let data = fs.readFileSync('./contracts/EthStorageConstants.sol', 'utf8');
  if (data.indexOf(startTime) === -1) {
    return;
  }
  data = data.replace(startTime, newStartTime);
  fs.writeFileSync('./contracts/EthStorageConstants.sol', data);

  // save time
  fs.writeFileSync(temp_time, newStartTime + "");
  console.log("Change start time success!");
});

task("undo", "Undo changes to startTime", async (taskArgs, hre) => {
  const startTime = "1713782077";
  const currentTime = fs.readFileSync(temp_time, "utf-8");

  // replace
  let data = fs.readFileSync('./contracts/EthStorageConstants.sol', 'utf8');
  if (data.indexOf(currentTime) === -1) {
    return;
  }
  data = data.replace(currentTime, startTime);
  fs.writeFileSync('./contracts/EthStorageConstants.sol', data);

  // remove
  fs.unlinkSync(temp_time);
  console.log("Undo change start time success!");
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      initialBaseFeePerGas: 0, // workaround from https://github.com/sc-forks/solidity-coverage/issues/652#issuecomment-896330136 . Remove when that issue is closed.
    },
    devnet: {
      url: process.env.EIP4844_DEVNET_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    rinkeby: {
      url: process.env.RINKEBY_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    goerli: {
      url: process.env.GOERLI_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    sepolia: {
      url: process.env.SEPOLIA_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },    
    kovan: {
      url: process.env.KOVAN_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    arbitrum: {
      url: process.env.ARBITRUM_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    ropsten: {
      url: process.env.ROPSTEN_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    optimism: {
      url: process.env.OPTIMISM_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  mocha: {
    grep: process.env.MOCHA_GREP || "",
    timeout: 120000,
  },
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "cancun",
    },
  },
};
