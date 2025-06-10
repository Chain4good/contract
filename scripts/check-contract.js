async function main() {
  const CharityDonation = await ethers.getContractFactory("CharityDonation");
  const contract = await CharityDonation.attach("0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9");

  console.log("\nContract Details:");
  console.log("----------------");
  console.log("Address:", contract.address);
  console.log("Owner:", await contract.owner());
  console.log("Lending Pool:", await contract.lendingPool());
  console.log("Fee Recipient:", await contract.platformFeeRecipient());

  const campaignCount = await contract.campaignCount();
  console.log("\nTotal Campaigns:", campaignCount.toString());

  // List all campaigns
  for (let i = 0; i < campaignCount; i++) {
    const campaign = await contract.campaigns(i);
    console.log(`\nCampaign #${i}:`);
    console.log("Title:", campaign.title);
    console.log("Creator:", campaign.creator);
    console.log("Goal:", ethers.formatEther(campaign.goal), "ETH");
    console.log(
      "Total Donated:",
      ethers.formatEther(campaign.totalDonated),
      "ETH"
    );
    console.log("Is Closed:", campaign.isClosed);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
