// scripts/deploy.js
async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying with account:", deployer.address);

  const Contract = await ethers.getContractFactory("CharityDonation");
  const contract = await Contract.deploy();

  console.log("Contract deployed to:", await contract.getAddress());
}

main();
