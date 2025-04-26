// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

contract CharityDonation {
    struct Campaign {
        address creator;
        string title;
        uint256 goal;
        uint256 deadline;
        uint256 totalDonated;
        bool isClosed;
        bool isNoLimit;
    }

    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(address => uint256)) public donations;
    mapping(uint256 => mapping(address => bool)) public refunded;
    uint256 public campaignCount;

    event DonationMade(uint256 campaignId, address donor, uint256 amount);
    event CampaignClosed(uint256 campaignId, bool reachedGoal);
    event RefundIssued(uint256 campaignId, address donor, uint256 amount);
    event FundsWithdrawn(uint256 campaignId, address creator, uint256 amount);

    function createCampaign(string memory _title, uint256 _goal, uint256 _duration, bool _isNoLimit) public {
        require(_goal > 0, "Goal must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");
        campaigns[campaignCount] = Campaign({
            creator: msg.sender,
            title: _title,
            goal: _goal,
            deadline: block.timestamp + _duration,
            totalDonated: 0,
            isClosed: false,
            isNoLimit: _isNoLimit
        });
        campaignCount++;
    }

    function donate(uint256 _campaignId) public payable {
        Campaign storage campaign = campaigns[_campaignId];
        require(!campaign.isClosed, "Campaign is closed");
        require(block.timestamp < campaign.deadline, "Campaign has ended");
        require(msg.value > 0, "Donation amount must be greater than 0");
        campaign.totalDonated += msg.value;
        donations[_campaignId][msg.sender] += msg.value;
        emit DonationMade(_campaignId, msg.sender, msg.value);
        if (!campaign.isNoLimit && campaign.totalDonated >= campaign.goal) {
            _withdrawFunds(_campaignId);
        }
    }

    function closeCampaign(uint256 _campaignId) public {
        Campaign storage campaign = campaigns[_campaignId];
        require(msg.sender == campaign.creator || block.timestamp >= campaign.deadline, 
                "Only creator can close before deadline");
        require(!campaign.isClosed, "Campaign already closed");
        campaign.isClosed = true;
        bool reachedGoal = campaign.totalDonated >= campaign.goal;
        emit CampaignClosed(_campaignId, reachedGoal);
        if (reachedGoal || campaign.isNoLimit) {
            _withdrawFunds(_campaignId);
        }
    }

    function _withdrawFunds(uint256 _campaignId) internal {
        Campaign storage campaign = campaigns[_campaignId];
        if (campaign.totalDonated > 0) {
            uint256 amount = campaign.totalDonated;
            campaign.totalDonated = 0;
            payable(campaign.creator).transfer(amount);
            emit FundsWithdrawn(_campaignId, campaign.creator, amount);
        }
    }

    function refund(uint256 _campaignId) public {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.isClosed || block.timestamp >= campaign.deadline, 
                "Campaign must be closed or ended");
        require(!campaign.isNoLimit && campaign.totalDonated < campaign.goal, 
                "No refund available for successful or unlimited campaigns");
        require(!refunded[_campaignId][msg.sender], "Already refunded");

        uint256 amount = donations[_campaignId][msg.sender];
        require(amount > 0, "No donation to refund");

        refunded[_campaignId][msg.sender] = true;
        
        payable(msg.sender).transfer(amount);
        emit RefundIssued(_campaignId, msg.sender, amount);
    }

    function getCampaignStatus(uint256 _campaignId) public view returns (
        bool isActive,
        bool isSuccessful,
        uint256 remainingTime
    ) {
        Campaign storage campaign = campaigns[_campaignId];
        isActive = !campaign.isClosed && block.timestamp < campaign.deadline;
        isSuccessful = campaign.totalDonated >= campaign.goal || campaign.isNoLimit;
        
        if (block.timestamp < campaign.deadline) {
            remainingTime = campaign.deadline - block.timestamp;
        } else {
            remainingTime = 0;
        }
        
    }
}