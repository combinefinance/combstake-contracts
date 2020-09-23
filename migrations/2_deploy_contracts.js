require('dotenv').config();

const CombToken = artifacts.require('CombToken');
const MasterChef = artifacts.require('MasterChef');

module.exports = async function (deployer) {
  await deployer.deploy(CombToken);
  await deployer.deploy(MasterChef, CombToken.address, 0);
};
