const { ethers } = require("hardhat");

async function main() {
  try {
    // Kết nối với Lending Pool using getContractAt
    const lendingPool = await ethers.getContractAt(
      "ILendingPool",
      "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
    );

    // Lấy thông tin lãi suất
    const liquidityRate = await lendingPool.getReserveData(ethers.ZeroAddress);
    console.log("\nLending Pool Details:");
    console.log("-------------------");
    console.log("Address:", await lendingPool.getAddress());
    console.log("Current APY:", ethers.formatUnits(liquidityRate, 25), "%");

    // Get CharityDonation contract
    const charityContract = await ethers.getContractAt(
      "CharityDonation",
      "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9"
    );

    const campaignCount = await charityContract.campaignCount();

    // Kiểm tra lợi nhuận của từng campaign
    for (let i = 0; i < campaignCount; i++) {
      const staked = await charityContract.stakedAmount(i);
      const lastUpdate = await charityContract.lastUpdateTime(i);
      const campaign = await charityContract.campaigns(i);

      console.log(`\nCampaign #${i}:`);
      console.log("Title:", campaign.title);
      console.log("Staked Amount:", ethers.formatEther(staked), "ETH");
      console.log(
        "Last Update:",
        new Date(Number(lastUpdate) * 1000).toLocaleString()
      );

      if (staked > 0n) {
        const timeStaked =
          BigInt(Math.floor(Date.now() / 1000)) - BigInt(lastUpdate);
        const apy = Number(ethers.formatUnits(liquidityRate, 25));

        // Convert staked to number for calculation
        const stakedInEth = Number(ethers.formatEther(staked));
        const timeInYears = Number(timeStaked) / (365 * 24 * 3600);

        // Calculate profit
        const estimatedProfit = stakedInEth * apy * timeInYears;

        console.log(
          "Time Staked:",
          timeInYears.toFixed(6),
          "years",
          "\nEstimated Profit:",
          estimatedProfit.toFixed(18),
          "ETH"
        );
      }
    }
  } catch (error) {
    console.error("Error checking pool profit:", error);
    console.error("Error details:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
