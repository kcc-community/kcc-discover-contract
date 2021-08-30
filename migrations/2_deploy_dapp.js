const { deployProxy, upgradeProxy } = require('@openzeppelin/truffle-upgrades');
const Dapp = artifacts.require("DappStore");
// const DappV2 = artifacts.require("DappStoreV2");

const priCategory = ["DeFi", "Infrastructure", "Tools"];
const secCategory = ["Exchange", "NFT", "Game", "Earn", "Lending", "DAO", "Wallet", "Community", "Others"];

module.exports = async function(deployer) {
    const app = await deployProxy(Dapp, [priCategory, secCategory], {deployer});
    // const inst = await upgradeProxy(app.address, DappV2);
}