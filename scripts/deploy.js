const hre = require("hardhat");

async function main() {
  const PokerGame = await hre.ethers.getContractFactory("PokerGame");
  const pokerGame = await PokerGame.deploy();

  await pokerGame.deployed();

  console.log("PokerGame deployed to:", pokerGame.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 