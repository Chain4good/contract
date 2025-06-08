// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ILendingPool {
    function deposit(address asset, uint256 amount, address onBehalfOf) external payable;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getReserveData(address asset) external view returns (uint256 liquidityRate);
}

/**
 * @title CharityDonation
 * @notice A contract for managing charitable campaigns with staking capabilities
 */
contract CharityDonation {
    struct Campaign {
        address creator;
        string title;
        address tokenAddress;
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

    address public lendingPool;
    address public platformFeeRecipient;
    mapping(uint256 => uint256) public stakedAmount;
    mapping(uint256 => uint256) public lastUpdateTime;

    event DonationMade(uint256 campaignId, address donor, uint256 amount);
    event CampaignClosed(uint256 campaignId, bool reachedGoal);
    event RefundIssued(uint256 campaignId, address donor, uint256 amount);
    event FundsWithdrawn(uint256 campaignId, address creator, uint256 amount, uint256 interestToPlatform);

    constructor(address _lendingPool, address _platformFeeRecipient) {
        lendingPool = _lendingPool;
        platformFeeRecipient = _platformFeeRecipient;
    }

    /**
     * @notice Creates a new charity campaign
     * @param _title The name of the campaign
     * @param _tokenAddress The token address for donations (address(0) for ETH)
     * @param _goal The funding goal amount
     * @param _duration Duration of the campaign in seconds
     * @param _isNoLimit If true, campaign has no maximum limit
     */
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
            donors: new address[](0)
        });
        campaignCount++;
    }

    /**
     * @notice Allows users to donate to a specific campaign
     * @param _campaignId The ID of the campaign to donate to
     * @param _amount The amount to donate
     * @dev Supports both ETH and ERC20 token donations
     */
    function donate(uint256 _campaignId, uint256 _amount) public payable {
        Campaign storage campaign = campaigns[_campaignId];
        require(!campaign.isClosed, "Campaign is closed");
        require(block.timestamp < campaign.deadline, "Campaign has ended");
        require(_amount > 0, "Amount must be greater than 0");

        if (campaign.tokenAddress == address(0)) {
            require(msg.value == _amount, "Mismatch ETH amount");
        } else {
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

        _depositToLendingPool(_campaignId);

        emit DonationMade(_campaignId, msg.sender, _amount);

        if (!campaign.isNoLimit && campaign.totalDonated >= campaign.goal) {
            _withdrawFunds(_campaignId);
        }
    }

    /**
     * @notice Closes a campaign either by creator or after deadline
     * @param _campaignId The ID of the campaign to close
     * @dev If goal is reached or campaign is unlimited, funds are withdrawn
     */
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

    /**
     * @notice Internal function to withdraw funds to campaign creator
     * @param _campaignId The ID of the campaign
     * @dev Withdraws staked funds from lending pool before transfer
     */
    function _withdrawFunds(uint256 _campaignId) internal {
        uint256 totalWithdrawn = _withdrawFromLendingPool(_campaignId);

        Campaign storage campaign = campaigns[_campaignId];
        uint256 interest = 0;
        uint256 principal = stakedAmount[_campaignId];
        if (totalWithdrawn > principal) {
            interest = totalWithdrawn - principal;
        }
        if (principal > 0) {
            campaign.totalDonated = 0;
            if (campaign.tokenAddress == address(0)) {
                payable(campaign.creator).transfer(principal);
            } else {
                IERC20(campaign.tokenAddress).transfer(campaign.creator, principal);
            }
        }
        if (interest > 0) {
            if (campaign.tokenAddress == address(0)) {
                payable(platformFeeRecipient).transfer(interest);
            } else {
                IERC20(campaign.tokenAddress).transfer(platformFeeRecipient, interest);
            }
        }
        emit FundsWithdrawn(_campaignId, campaign.creator, principal, interest);
    }

    /**
     * @notice Allows donors to get refund if campaign fails
     * @param _campaignId The ID of the campaign
     * @dev Only available if campaign is closed/ended and goal not reached
     */
    function refund(uint256 _campaignId) public {
        uint256 totalWithdrawn = _withdrawFromLendingPool(_campaignId);

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

        uint256 interest = 0;
        uint256 principal = stakedAmount[_campaignId];
        if (totalWithdrawn > principal) {
            interest = totalWithdrawn - principal;
            if (interest > 0) {
                if (campaign.tokenAddress == address(0)) {
                    payable(platformFeeRecipient).transfer(interest);
                } else {
                    IERC20(campaign.tokenAddress).transfer(platformFeeRecipient, interest);
                }
            }
        }
        emit RefundIssued(_campaignId, msg.sender, amount);
    }

    /**
     * @notice Gets list of donors for a campaign
     * @param _campaignId The ID of the campaign
     * @return Array of donor addresses
     */
    function getDonors(uint256 _campaignId) public view returns (address[] memory) {
        return campaigns[_campaignId].donors;
    }

    /**
     * @notice Gets current status of a campaign
     * @param _campaignId The ID of the campaign
     * @return isActive Whether campaign is still active
     * @return isSuccessful Whether campaign reached its goal
     * @return remainingTime Time left until campaign ends
     */
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

    /**
     * @notice Internal function to deposit funds into lending pool
     * @param _campaignId The ID of the campaign
     * @dev Handles both ETH and ERC20 deposits
     */
    function _depositToLendingPool(uint256 _campaignId) internal {
        Campaign storage campaign = campaigns[_campaignId];
        uint256 amount = campaign.totalDonated - stakedAmount[_campaignId];

        if(amount > 0) {
            if(campaign.tokenAddress == address(0)) {
                ILendingPool(lendingPool).deposit{value: amount}(
                    address(0), 
                    amount,
                    address(this)
                );
            } else {
                IERC20(campaign.tokenAddress).approve(lendingPool, amount);
                ILendingPool(lendingPool).deposit(
                    campaign.tokenAddress,
                    amount, 
                    address(this)
                );
            }

            stakedAmount[_campaignId] += amount;
            lastUpdateTime[_campaignId] = block.timestamp;
        }
    }

    /**
     * @notice Internal function to withdraw funds from lending pool
     * @param _campaignId The ID of the campaign
     * @return Amount withdrawn from lending pool
     */
    function _withdrawFromLendingPool(uint256 _campaignId) internal returns(uint256) {
        uint256 principal = stakedAmount[_campaignId];
        if(principal > 0) {
            Campaign storage campaign = campaigns[_campaignId];
            uint256 totalWithdrawn = ILendingPool(lendingPool).withdraw(
                campaign.tokenAddress,
                principal,
                address(this)
            );
            stakedAmount[_campaignId] = 0;
            return totalWithdrawn;
        }
        return 0;
    }
}
