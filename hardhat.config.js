require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();
const { GOERLI_URL, PRIVATE_KEY, ETHERSCAN_API_KEY } = process.env;
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.17",
  defaultNetwork: "hardhat",
  networks: {
    goerli: {
      url: GOERLI_URL || "",
      accounts: [`0x${PRIVATE_KEY}`]
    }
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY
  }
};
