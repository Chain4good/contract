// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Interface for ERC20 tokens
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

// Interface for a generic lending pool like Aave
interface ILendingPool {
    function deposit(address asset, uint256 amount, address onBehalfOf) external payable;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getReserveData(address asset) external view returns (uint256 liquidityRate);
}

/**
 * @title CharityDonation   
 * @notice A contract for managing charitable campaigns with staking capabilities in a lending pool.
 */
contract CharityDonation {
    // --- CUSTOM ERRORS DEFINITIONS ---
    error NotOwner(address sender);
    error InvalidAddress();
    error GoalMustBeGreaterThanZero();
    error DurationMustBeGreaterThanZero();
    error CampaignIsClosed(uint256 campaignId);
    error CampaignHasEnded(uint256 campaignId, uint256 deadline, uint256 blockTimestamp);
    error AmountMustBeGreaterThanZero();
    error MismatchedEthAmount(uint256 required, uint256 sent);
    error EthSentToTokenCampaign();
    error TokenTransferFailed(address token, address from, address to, uint256 amount);
    error OnlyCreatorCanCloseBeforeDeadline(address sender, address creator);
    error CampaignAlreadyClosed(uint256 campaignId);
    error NoRefundForSuccessfulOrUnlimitedCampaign(uint256 campaignId);
    error AlreadyRefunded(uint256 campaignId, address donor);
    error NoDonationToRefund(address donor);
    error CampaignNotOverOrIsSuccessful();


    // --- STATE VARIABLES ---
    struct Campaign {
        address creator;
        string title;
        address tokenAddress; // address(0) for ETH
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

    address public owner;

    // --- EVENTS ---
    event DonationMade(uint256 indexed campaignId, address indexed donor, uint256 amount);
    event CampaignCreated(uint256 indexed campaignId, address indexed creator, string title, uint256 goal, uint256 deadline);
    event CampaignClosed(uint256 indexed campaignId, bool reachedGoal);
    event RefundIssued(uint256 indexed campaignId, address indexed donor, uint256 amount);
    event FundsWithdrawn(uint256 indexed campaignId, address indexed creator, uint256 principal, uint256 interestToPlatform);
    event LendingPoolUpdated(address oldPool, address newPool);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    // --- MODIFIERS ---
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    // --- FUNCTIONS ---
    constructor(address _lendingPool, address _platformFeeRecipient) {
        if (_lendingPool == address(0) || _platformFeeRecipient == address(0)) revert InvalidAddress();
        owner = msg.sender;
        lendingPool = _lendingPool;
        platformFeeRecipient = _platformFeeRecipient;
    }

    /**
     * @notice Creates a new charity campaign.
     * @param _title The name of the campaign.
     * @param _tokenAddress The token address for donations (address(0) for ETH).
     * @param _goal The funding goal amount.
     * @param _duration Duration of the campaign in seconds.
     * @param _isNoLimit If true, campaign has no maximum limit.
     */
    function createCampaign(
        string memory _title,
        address _tokenAddress,
        uint256 _goal,
        uint256 _duration,
        bool _isNoLimit
    ) public {
        if (!_isNoLimit && _goal == 0) revert GoalMustBeGreaterThanZero();
        if (_duration == 0) revert DurationMustBeGreaterThanZero();

        uint256 deadline = block.timestamp + _duration;
        campaigns[campaignCount] = Campaign({
            creator: msg.sender,
            title: _title,
            tokenAddress: _tokenAddress,
            goal: _goal,
            deadline: deadline,
            totalDonated: 0,
            isClosed: false,
            isNoLimit: _isNoLimit,
            donors: new address[](0)
        });
        
        emit CampaignCreated(campaignCount, msg.sender, _title, _goal, deadline);
        campaignCount++;
    }

    /**
     * @notice Allows users to donate to a specific campaign.
     * @param _campaignId The ID of the campaign to donate to.
     * @param _amount The amount to donate.
     */
    function donate(uint256 _campaignId, uint256 _amount) public payable {
        Campaign storage campaign = campaigns[_campaignId];
        if (campaign.isClosed) revert CampaignIsClosed(_campaignId);
        if (block.timestamp >= campaign.deadline) revert CampaignHasEnded(_campaignId, campaign.deadline, block.timestamp);
        if (_amount == 0) revert AmountMustBeGreaterThanZero();

        if (campaign.tokenAddress == address(0)) {
            if (msg.value != _amount) revert MismatchedEthAmount(_amount, msg.value);
        } else {
            if (msg.value != 0) revert EthSentToTokenCampaign();
            bool success = IERC20(campaign.tokenAddress).transferFrom(msg.sender, address(this), _amount);
            if (!success) revert TokenTransferFailed(campaign.tokenAddress, msg.sender, address(this), _amount);
        }

        campaign.totalDonated += _amount;
        donations[_campaignId][msg.sender] += _amount;

        if (!hasDonated[_campaignId][msg.sender]) {
            campaign.donors.push(msg.sender);
            hasDonated[_campaignId][msg.sender] = true;
        }

        _depositToLendingPool(_campaignId, _amount);

        emit DonationMade(_campaignId, msg.sender, _amount);

        if (!campaign.isNoLimit && campaign.totalDonated >= campaign.goal) {
            campaign.isClosed = true;
            _withdrawFunds(_campaignId);
            emit CampaignClosed(_campaignId, true);
        }
    }

    /**
     * @notice Closes a campaign either by the creator or after the deadline has passed.
     * @param _campaignId The ID of the campaign to close.
     */
    function closeCampaign(uint256 _campaignId) public {
        Campaign storage campaign = campaigns[_campaignId];
        if (msg.sender != campaign.creator && block.timestamp < campaign.deadline) {
            revert OnlyCreatorCanCloseBeforeDeadline(msg.sender, campaign.creator);
        }
        if (campaign.isClosed) revert CampaignAlreadyClosed(_campaignId);

        campaign.isClosed = true;
        bool reachedGoal = campaign.totalDonated >= campaign.goal;
        emit CampaignClosed(_campaignId, reachedGoal);

        if (reachedGoal || campaign.isNoLimit) {
            _withdrawFunds(_campaignId);
        }
    }

    /**
     * @notice Allows donors to get a refund if a campaign fails.
     * @param _campaignId The ID of the campaign.
     */
    function refund(uint256 _campaignId) public {
        Campaign storage campaign = campaigns[_campaignId];
        if (!campaign.isClosed && block.timestamp < campaign.deadline) {
            revert CampaignNotOverOrIsSuccessful();
        }
        if (campaign.isNoLimit || campaign.totalDonated >= campaign.goal) {
            revert NoRefundForSuccessfulOrUnlimitedCampaign(_campaignId);
        }
        if (refunded[_campaignId][msg.sender]) revert AlreadyRefunded(_campaignId, msg.sender);
        
        uint256 amountToRefund = donations[_campaignId][msg.sender];
        if (amountToRefund == 0) revert NoDonationToRefund(msg.sender);

        refunded[_campaignId][msg.sender] = true;
        
        // In a real-world, complex scenario, you'd withdraw the total pool funds once
        // and distribute refunds from the contract balance to save gas.
        // This simplified version withdraws on the first refund call.
        if (stakedAmount[_campaignId] > 0) {
            _withdrawFromLendingPool(_campaignId);
        }

        if (campaign.tokenAddress == address(0)) {
            payable(msg.sender).transfer(amountToRefund);
        } else {
            IERC20(campaign.tokenAddress).transfer(msg.sender, amountToRefund);
        }

        emit RefundIssued(_campaignId, msg.sender, amountToRefund);
    }

    /**
     * @notice Internal function to withdraw funds to the campaign creator and fees to the platform.
     * @param _campaignId The ID of the campaign.
     */
    function _withdrawFunds(uint256 _campaignId) internal {
        uint256 totalWithdrawn = _withdrawFromLendingPool(_campaignId);

        Campaign storage campaign = campaigns[_campaignId];
        uint256 principal = campaign.totalDonated;
        
        if (principal > 0) {
            uint256 interest = totalWithdrawn > principal ? totalWithdrawn - principal : 0;
            
            // Transfer principal to creator
            if (campaign.tokenAddress == address(0)) {
                payable(campaign.creator).transfer(principal);
            } else {
                IERC20(campaign.tokenAddress).transfer(campaign.creator, principal);
            }
            
            // Transfer interest to platform
            if (interest > 0) {
                if (campaign.tokenAddress == address(0)) {
                    payable(platformFeeRecipient).transfer(interest);
                } else {
                    IERC20(campaign.tokenAddress).transfer(platformFeeRecipient, interest);
                }
            }
            emit FundsWithdrawn(_campaignId, campaign.creator, principal, interest);
        }
    }

    /**
     * @notice Internal function to deposit funds into the lending pool.
     * @param _campaignId The ID of the campaign.
     * @param _amount The amount being deposited.
     */
    function _depositToLendingPool(uint256 _campaignId, uint256 _amount) internal {
        if (lendingPool != address(0) && _amount > 0) {
            Campaign storage campaign = campaigns[_campaignId];
            if (campaign.tokenAddress == address(0)) {
                ILendingPool(lendingPool).deposit{value: _amount}(address(this), _amount, address(this));
            } else {
                IERC20 token = IERC20(campaign.tokenAddress);
                token.approve(lendingPool, _amount);
                ILendingPool(lendingPool).deposit(campaign.tokenAddress, _amount, address(this));
            }
            stakedAmount[_campaignId] += _amount;
            lastUpdateTime[_campaignId] = block.timestamp;
        }
    }

    /**
     * @notice Internal function to withdraw all staked funds from the lending pool for a campaign.
     * @param _campaignId The ID of the campaign.
     * @return totalWithdrawn The total amount withdrawn including interest.
     */
    function _withdrawFromLendingPool(uint256 _campaignId) internal returns (uint256) {
        uint256 principal = stakedAmount[_campaignId];
        if (lendingPool != address(0) && principal > 0) {
            Campaign storage campaign = campaigns[_campaignId];
            uint256 totalWithdrawn = ILendingPool(lendingPool).withdraw(
                campaign.tokenAddress == address(0) ? address(this) : campaign.tokenAddress,
                principal,
                address(this)
            );
            stakedAmount[_campaignId] = 0;
            return totalWithdrawn;
        }
        return principal; // Return principal if no lending pool or nothing to withdraw
    }
    
    // --- ADMIN FUNCTIONS ---
    function updateLendingPool(address _newLendingPool) external onlyOwner {
        if (_newLendingPool == address(0)) revert InvalidAddress();
        address oldPool = lendingPool;
        lendingPool = _newLendingPool;
        emit LendingPoolUpdated(oldPool, _newLendingPool);
    }

    function updateFeeRecipient(address _newRecipient) external onlyOwner {
        if (_newRecipient == address(0)) revert InvalidAddress();
        address oldRecipient = platformFeeRecipient;
        platformFeeRecipient = _newRecipient;
        emit FeeRecipientUpdated(oldRecipient, _newRecipient);
    }

    // --- VIEW FUNCTIONS ---
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
        remainingTime = block.timestamp < campaign.deadline ? campaign.deadline - block.timestamp : 0;
    }
}