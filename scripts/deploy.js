// scripts/deploy.js
require("dotenv").config();
const { ethers, network, run } = require("hardhat");

async function main() {
  try {
    const lendingPool = process.env.LENDING_POOL_ADDRESS;
    const platformFeeRecipient = process.env.PLATFORM_FEE_RECIPIENT_ADDRESS;

    console.log("Deploying contracts...");
    const CharityDonation = await ethers.getContractFactory("CharityDonation");
    const charityDonation = await CharityDonation.deploy(
      lendingPool,
      platformFeeRecipient
    );

    console.log("Waiting for deployment confirmations...");
    // Wait for 5 block confirmations
    await charityDonation.waitForDeployment();
    const receipt = await charityDonation.deploymentTransaction().wait(5);

    console.log(
      `CharityDonation deployed to: ${await charityDonation.getAddress()}`
    );

    // Add delay before verification
    if (network.name !== "localhost" && process.env.ETHERSCAN_API_KEY) {
      console.log("Waiting 60 seconds before verification...");
      await new Promise((resolve) => setTimeout(resolve, 60000)); // 60 second delay

      try {
        await verify(await charityDonation.getAddress(), [
          lendingPool,
          platformFeeRecipient,
        ]);
      } catch (error) {
        console.log("Verification failed:", error);
      }
    }
  } catch (error) {
    console.error(error);
    process.exit(1);
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
      console.log("Contract is already verified!");
    } else {
      console.error("Verification error:", e);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
