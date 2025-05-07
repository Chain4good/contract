// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract CharityDonation {
    struct Campaign {
        address creator;
        string title;
        address tokenAddress; // address(0) = ETH
        uint256 goal;
        uint256 deadline;
        uint256 totalDonated;
        bool isClosed;
        bool isNoLimit;
        address[] donors;
    }

    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(address => uint256)) public donations;
    mapping(uint256 => mapping(address => bool)) public refunded;
    mapping(uint256 => mapping(address => bool)) public hasDonated;
    uint256 public campaignCount;

    event DonationMade(uint256 campaignId, address donor, uint256 amount);
    event CampaignClosed(uint256 campaignId, bool reachedGoal);
    event RefundIssued(uint256 campaignId, address donor, uint256 amount);
    event FundsWithdrawn(uint256 campaignId, address creator, uint256 amount);

    function createCampaign(
        string memory _title,
        address _tokenAddress,
        uint256 _goal,
        uint256 _duration,
        bool _isNoLimit
    ) public {
        require(_goal > 0, "Goal must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");

        campaigns[campaignCount] = Campaign({
            creator: msg.sender,
            title: _title,
            tokenAddress: _tokenAddress,
            goal: _goal,
            deadline: block.timestamp + _duration,
            totalDonated: 0,
            isClosed: false,
            isNoLimit: _isNoLimit,
            donors: new address 
        });
        campaignCount++;
    }

    function donate(uint256 _campaignId, uint256 _amount) public payable {
        Campaign storage campaign = campaigns[_campaignId];
        require(!campaign.isClosed, "Campaign is closed");
        require(block.timestamp < campaign.deadline, "Campaign has ended");
        require(_amount > 0, "Amount must be greater than 0");

        if (campaign.tokenAddress == address(0)) {
            // ETH donation
            require(msg.value == _amount, "Mismatch ETH amount");
        } else {
            // ERC20 donation
            require(msg.value == 0, "Do not send ETH");
            require(
                IERC20(campaign.tokenAddress).transferFrom(msg.sender, address(this), _amount),
                "Token transfer failed"
            );
        }

        campaign.totalDonated += _amount;
        donations[_campaignId][msg.sender] += _amount;

        if (!hasDonated[_campaignId][msg.sender]) {
            campaign.donors.push(msg.sender);
            hasDonated[_campaignId][msg.sender] = true;
        }

        emit DonationMade(_campaignId, msg.sender, _amount);

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
        uint256 amount = campaign.totalDonated;
        if (amount > 0) {
            campaign.totalDonated = 0;
            if (campaign.tokenAddress == address(0)) {
                payable(campaign.creator).transfer(amount);
            } else {
                IERC20(campaign.tokenAddress).transfer(campaign.creator, amount);
            }
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

        if (campaign.tokenAddress == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(campaign.tokenAddress).transfer(msg.sender, amount);
        }

        emit RefundIssued(_campaignId, msg.sender, amount);
    }

    function getDonors(uint256 _campaignId) public view returns (address[] memory) {
        return campaigns[_campaignId].donors;
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
