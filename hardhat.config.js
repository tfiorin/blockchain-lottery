require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();

const privateKey = process.env.PRIVATE_KEY || "";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.19",
  networks: {
    hardhat: {
        chainId: 31337,
    },
    localhost: {
        chainId: 31337,
    }
  }
};