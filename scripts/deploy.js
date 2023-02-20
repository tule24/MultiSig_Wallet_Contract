const hre = require("hardhat");

async function main() {
  const MultiSigFactory = await hre.ethers.getContractFactory("MultiSigFactory")
  const multiSigFactory = await MultiSigFactory.deploy()

  await multiSigFactory.deployed();

  console.log(
    `MultiSigFactory deployed to ${multiSigFactory.address}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
