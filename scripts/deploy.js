// scripts/deploy.js
async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const CharityDonation = await ethers.getContractFactory("CharityDonation");
  const charityDonation = await CharityDonation.deploy();

  console.log(
    "CharityDonation deployed to:",
    await charityDonation.getAddress()
  );

  // Wait for deployment to be mined and get confirmations
  console.log("Waiting for deployment confirmations...");
  await charityDonation.waitForDeployment();

  // Get receipt and wait for additional confirmations
  const deployTxReceipt = await charityDonation.deploymentTransaction().wait(6);
  console.log(`Deployment confirmed in block: ${deployTxReceipt.blockNumber}`);

  // Verify contract on Etherscan
  if (network.name !== "localhost") {
    try {
      await verify(await charityDonation.getAddress(), []);
    } catch (error) {
      console.log("Error verifying contract:", error);
    }
  }
}

async function verify(contractAddress, args) {
  console.log("Verifying contract...");
  try {
    await run("verify:verify", {
      address: contractAddress,
      constructorArguments: args,
    });
  } catch (e) {
    if (e.message.toLowerCase().includes("already verified")) {
      console.log("Already verified!");
    } else {
      console.log(e);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
