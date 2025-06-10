async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // 1. Deploy Mock Lending Pool first
  const MockLendingPool = await ethers.getContractFactory("MockLendingPool");
  const mockLendingPool = await MockLendingPool.deploy();
  await mockLendingPool.waitForDeployment();
  console.log(
    "MockLendingPool deployed to:",
    await mockLendingPool.getAddress()
  );

  // 2. Deploy CharityDonation
  const CharityDonation = await ethers.getContractFactory("CharityDonation");
  const charityDonation = await CharityDonation.deploy(
    await mockLendingPool.getAddress(), // Lending pool address
    deployer.address // Platform fee recipient address
  );
  await charityDonation.waitForDeployment();

  const charityAddress = await charityDonation.getAddress();
  console.log("CharityDonation deployed to:", charityAddress);

  // Update check-contract.js with this address
  const fs = require("fs");
  const checkContractPath = "./scripts/check-contract.js";
  let content = fs.readFileSync(checkContractPath, "utf8");
  content = content.replace(
    /CharityDonation\.attach\([^\)]+\)/,
    `CharityDonation.attach("${charityAddress}")`
  );
  fs.writeFileSync(checkContractPath, content);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
