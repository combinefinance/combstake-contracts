require('dotenv').config();

const HDWalletProvider = require("@truffle/hdwallet-provider");

(module.exports = {
  compilers: {
    solc: {
      version: '0.6.12',
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
      },
    },
  },
  plugins: [
    'truffle-plugin-verify',
  ],
  networks: {
    development: {
      host: 'localhost',
      port: 8545,
      network_id: 50,
    },
    ropsten: {
      provider: new HDWalletProvider(
        process.env.OWNER_PRIVATE_KEY,
        `https://ropsten.infura.io/v3/${process.env.INFURA_KEY}`
      ),
      network_id: 3,
    },
    mainnetsten: {
      provider: new HDWalletProvider(
        process.env.OWNER_PRIVATE_KEY,
        `https://mainnet.infura.io/v3/${process.env.INFURA_KEY}`
      ),
      network_id: 1,
    },
  },
  api_keys: {
    etherscan: process.env.ETHERSCAN_API_KEY,
  },
});
