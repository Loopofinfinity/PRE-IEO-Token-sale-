// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IUSDT {
    function transfer(address payable recipient, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract LOIPreIEO is Context, Ownable {
    using SafeMath for uint256;

    // Custom error for when the LOI token is not active
    error LOINotActive();

    // LOI Token Contract Address
    address public LOIContract;

    // USDT Token Contract Address
    IUSDT private USDTContract;

    // Whitelisted Investors
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public vestedAmount;
    mapping(address => uint256) public vestingStart;
    mapping(address => uint256) public vestingEnd;

    // Maximum Number of Investors
    uint256 public maxInvestors = 10000;

    // Maximum Investment per User
    uint256 public maxInvestment = 10000 * 10**18; // $10,000

    // Minimum Investment per User
    uint256 public minInvestment = 10 * 10**18; // $10

    // Total Tokens for Pre-sale
    uint256 public totalTokens;

    // Tokens Sold in Pre-sale
    uint256 public tokensSold;

    // Pre-IEO Round Status
    bool public preIEOActive;

    // Time-lock mechanism
    uint256 public destroyTime;

    // Vesting period duration in seconds
    uint256 public vestingPeriod = 90 days; // Updated to 3 months (90 days)

    // Vesting cliff duration in seconds
    uint256 public constant vestingCliff = 30 days; // Updated to 1 month (30 days)

    // Token price
    uint256 public tokenPrice = 8000000000000000000; // $0.0080 per token, in USDT

    // Investor counter
    uint256 public investorCount;

    // Events
    event TokensPurchased(address indexed investor, uint256 amount);
    event VestingStarted(address indexed investor, uint256 vestedAmount, uint256 vestingStart);

    constructor(address _owner, address _LOIContract) {
    LOIContract = _LOIContract;
    investorCount = 0;
    preIEOActive = false; // Initialize preIEOActive variable
    transferOwnership(_owner); // Add this line to set the initial owner
}

    modifier isLOIActive() {
        require(preIEOActive, "LOI token is not active");
        _;
    }

    modifier isWhitelisted() {
        require(whitelist[_msgSender()], "Investor not whitelisted");
        _;
    }

    modifier onlyOwnerOfVestedTokens(address _investor) {
        require(_msgSender() == _investor, "Only owner of vested tokens can call this function");
        _;
    }

    modifier isVestingActive(address investor) {
        require(block.timestamp >= vestingStart[investor], "Vesting period has not started yet");
        require(block.timestamp < vestingEnd[investor], "Vesting period has ended");
        require(vestedAmount[investor] > 0, "No vested tokens for the investor");
        _;
    }

    modifier refundInvestor() {
        require(_msgSender() == owner(), "Only contract owner can refund investor");
        _;
    }

    // Set the USDT Token Contract Address
    function set_USDTContract(address _USDTContract) external onlyOwner {
        require(_USDTContract != address(0), "Invalid USDT contract address");
        USDTContract = IUSDT(_USDTContract);
    }

    // Set the LOI Token Contract Address
    function set_LOIContract(address _LOIContract) external onlyOwner {
        LOIContract = _LOIContract;
    }

    // Whitelist an Investor
    function whitelistInvestor(address _investor) external onlyOwner {
        require(_investor != address(0), "Invalid investor address");
        whitelist[_investor] = true;
    }

    // Remove an Investor from Whitelist
    function removeInvestorFromWhitelist(address _investor) external onlyOwner {
        require(_investor != address(0), "Invalid investor address");
        require(whitelist[_investor], "Investor is not whitelisted"); // Added check for existing whitelist entry
        whitelist[_investor] = false;
    }

    // Set the Maximum Number of Investors
    function setMaxInvestors(uint256 _maxInvestors) external onlyOwner {
        require(_maxInvestors >= investorCount, "Cannot set max investors lower than the current investor count");
        require(_maxInvestors > 0, "Invalid max investors value");
        maxInvestors = _maxInvestors;
    }

    // Set the Maximum Investment per User
    function setMaxInvestment(uint256 _maxInvestment) external onlyOwner {
        require(_maxInvestment > 0, "Invalid max investment amount");
        maxInvestment = _maxInvestment;
    }

    function setMinInvestment(uint256 _minInvestment) external onlyOwner {
        require(_minInvestment > 0, "Invalid min investment amount");
        minInvestment = _minInvestment;
    }

    function startPreIEO(uint256 _totalTokens, uint256 _destroyTime) external onlyOwner {
        require(!preIEOActive, "Pre-IEO already active");
        require(_totalTokens > 0, "Invalid total tokens");
        require(_destroyTime > block.timestamp, "Invalid destroy time");

        // Check if the contract has sufficient USDT balance
        uint256 requiredUSDT = SafeMath.mul(_totalTokens, tokenPrice);
        require(IUSDT(USDTContract).balanceOf(address(this)) >= requiredUSDT, "Insufficient USDT balance");

        totalTokens = _totalTokens; // Assign the provided totalTokens value
        tokensSold = 0;
        preIEOActive = true;
        destroyTime = _destroyTime;
    }

    // Stop the Pre-IEO Round
    uint256 private constant COOLDOWN_PERIOD = 24 hours;
    uint256 private cooldownEndTime;

    function stopPreIEO() external onlyOwner {
        require(preIEOActive, "Pre-IEO not active");
        require(block.timestamp < cooldownEndTime, "Cooldown period has not ended");

        preIEOActive = false;
        cooldownEndTime = block.timestamp + COOLDOWN_PERIOD;
    }

    // Purchase Tokens in Pre-IEO Round with USDT
    function purchaseTokens() external isWhitelisted {
        uint256 amount = IUSDT(USDTContract).balanceOf(_msgSender());
        require(amount >= minInvestment, "Amount is less than the minimum investment amount");
        require(amount <= maxInvestment, "Amount is more than the maximum investment amount");

        // Adjust the precision to match the number of decimal places in tokenPrice
        uint256 precision = 10**18;
        uint256 tokensToBuy = amount.mul(precision).div(tokenPrice);

        // Adjust the tokensToBuy based on the number of decimal places in the LOI token
        uint256 tokenDecimals = 18; // Assuming the LOI token has 18 decimal places
        tokensToBuy = tokensToBuy.div(10**(18 - tokenDecimals));

        // Apply tier-based bonus
        uint256 bonusPercentage;
        if (amount >= 10 * 10**18 && amount <= 999 * 10**18) {
            bonusPercentage = 42;
        } else if (amount >= 1000 * 10**18 && amount <= 4999 * 10**18) {
            bonusPercentage = 62;
        } else if (amount >= 5000 * 10**18 && amount <= 10000 * 10**18) {
            bonusPercentage = 82;
        } else {
            bonusPercentage = 0;
        }

        // Calculate bonus tokens using SafeMath
        uint256 bonusTokens = SafeMath.div(SafeMath.mul(tokensToBuy, bonusPercentage), 100);

        // Ensure that the number of tokens to buy is within the available limit using SafeMath
        require(
            SafeMath.add(tokensSold, SafeMath.add(tokensToBuy, bonusTokens)) <= totalTokens,
            "Not enough tokens left for sale or arithmetic overflow"
        );

        // Update the number of tokens sold and the investor's vested amount
        tokensSold = SafeMath.add(tokensSold, SafeMath.add(tokensToBuy, bonusTokens));
        if (vestedAmount[_msgSender()] == 0) {
            investorCount = SafeMath.add(investorCount, 1);
        }
        vestedAmount[_msgSender()] = SafeMath.add(vestedAmount[_msgSender()], SafeMath.add(tokensToBuy, bonusTokens));
        vestingStart[_msgSender()] = block.timestamp.add(vestingCliff);

        // Transfer USDT from the investor to the contract
        require(
            USDTContract.transferFrom(_msgSender(), address(this), amount),
            "Failed to transfer USDT"
        );

        // Transfer tokens to the investor
        require(
            IERC20(LOIContract).transfer(_msgSender(), SafeMath.add(tokensToBuy, bonusTokens)),
            "Failed to transfer tokens"
        );

        // Emit event
        emit TokensPurchased(_msgSender(), SafeMath.add(tokensToBuy, bonusTokens));
        emit VestingStarted(_msgSender(), vestedAmount[_msgSender()], vestingStart[_msgSender()]);
    }

    // Withdraw USDT from Contract
    function withdrawUSDT() external onlyOwner {
        address payable ownerAddress = payable(owner());
        USDTContract.transfer(ownerAddress, IUSDT(USDTContract).balanceOf(address(this)));
    }

    // Withdraw Tokens from Contract
    function withdrawTokens(uint256 _amount) external onlyOwner isLOIActive {
        require(block.timestamp >= destroyTime, "Tokens are still locked");
        uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
        require(_amount <= LOIBalance, "Insufficient LOI tokens in contract");
        require(_amount <= vestedAmount[owner()], "Insufficient vested tokens");

        // Update the vested amount of the owner
        vestedAmount[owner()] = vestedAmount[owner()].sub(_amount);

        require(IERC20(LOIContract).transfer(owner(), _amount), "Token transfer failed");
    }

    // Get the Balance of LOI Tokens in Contract
    function getLOIBalance() external view returns (uint256) {
        return IERC20(LOIContract).balanceOf(address(this));
    }

    // Get the USDT Balance of Contract
    function getUSDTBalance() external view returns (uint256) {
        return USDTContract.balanceOf(address(this));
    }

    function startVesting() external {
        require(preIEOActive == false, "Pre-IEO still active");

        // Check if vesting has already started for the caller
        require(vestingStart[_msgSender()] == 0, "Vesting already started for investor");

        // Set vesting start time for the calling investor
        vestingStart[_msgSender()] = block.timestamp;

        // Set vesting end time based on vesting period
        vestingEnd[_msgSender()] = vestingStart[_msgSender()].add(vestingPeriod);

        // Initialize vestedAmount for the investor to maximum tokens purchased in Pre-IEO round
        vestedAmount[_msgSender()] = maxInvestment.div(tokenPrice);

        emit VestingStarted(_msgSender(), vestedAmount[_msgSender()], vestingStart[_msgSender()]);
    }

    function calculateVestedTokens(address investor) public view returns (uint256) {
        if (vestingStart[investor] == 0) {
            return 0; // Vesting has not started yet, return 0
        }

        uint256 elapsedTime = block.timestamp.sub(vestingStart[investor]);

        if (elapsedTime < vestingCliff) {
            return 0; // Vesting period has not reached the cliff, return 0
        }

        uint256 vestedTokens = 0;

        if (elapsedTime >= vestingEnd[investor]) {
            vestedTokens = vestedAmount[investor];
        } else {
            uint256 vestedDuration = vestingEnd[investor].sub(vestingStart[investor]);
            vestedTokens = vestedAmount[investor].mul(elapsedTime).div(vestedDuration);
        }

        return vestedTokens;
    }

    function getVestedAmount() external view isWhitelisted returns (uint256) {
        return vestedAmount[_msgSender()];
    }

    // Unlock Vested Tokens for a Specific Investor
    function unlockTokens() external {
        require(block.timestamp >= vestingEnd[_msgSender()], "Vesting period not over yet");

        uint256 tokensToUnlock = calculateVestedTokens(_msgSender());

        require(tokensToUnlock > 0, "No vested tokens to unlock");

        vestedAmount[_msgSender()] = vestedAmount[_msgSender()].sub(tokensToUnlock);

        // Transfer Tokens to Investor
        uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
        require(LOIBalance >= tokensToUnlock, "Insufficient LOI tokens in contract");
        require(IERC20(LOIContract).transfer(_msgSender(), tokensToUnlock), "Token transfer failed");
    }

    // Withdraw Vested Tokens for a Specific Investor
    function withdrawVestedTokens() external isVestingActive(_msgSender()) {
        require(block.timestamp >= vestingEnd[_msgSender()], "Vesting period not over yet");

        uint256 tokensToWithdraw = calculateVestedTokens(_msgSender());
        require(tokensToWithdraw > 0, "No vested tokens to withdraw");

        vestedAmount[_msgSender()] = vestedAmount[_msgSender()].sub(tokensToWithdraw);

        // Transfer Tokens to Investor
        uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
        require(LOIBalance >= tokensToWithdraw, "Insufficient LOI tokens in contract");
        require(IERC20(LOIContract).transfer(_msgSender(), tokensToWithdraw), "Token transfer failed");
    }

    // Get the number of tokens that have vested for an investor
    function getVestedTokens(address _investor) external view returns (uint256) {
        return vestedAmount[_investor];
    }

    // Function to destroy contract
    function destroyContract() external onlyOwner {
        uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
        require(LOIBalance > 0, "No LOI tokens in contract");

        // Check if the contract has already been destroyed
        require(destroyTime != 0, "Contract has already been destroyed");

        // Check if the destroy time has passed
        require(block.timestamp >= destroyTime, "Contract cannot be destroyed yet");

        // Clear the destroy time to prevent re-entry
        destroyTime = 0;

        // Transfer remaining LOI tokens to owner
        require(IERC20(LOIContract).transfer(owner(), LOIBalance), "Token transfer failed");

        // Transfer any remaining USDT to owner
        uint256 USDTBalance = IUSDT(USDTContract).balanceOf(address(this));
        if (USDTBalance > 0) {
            require(IUSDT(USDTContract).transfer(payable(owner()), USDTBalance), "USDT transfer failed");
        }

        // Transfer any remaining ether to owner
        uint256 etherBalance = address(this).balance;
        if (etherBalance > 0) {
            payable(owner()).transfer(etherBalance);
        }

        // Set destroyTime to 0 to mark the contract as destroyed
        destroyTime = 0;
    }

    // Fallback Function
    fallback() external payable {}

    // Receive Function
    receive() external payable {}
}
