// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol"; // Import Context.sol from OpenZeppelin
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
    IUSDT public USDTContract;

    // Whitelisted Investors
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public vestedAmount;
    mapping(address => uint256) public vestingStart;
    mapping(address => uint256) public vestingEnd;

    // Maximum Number of Investors
    uint256 public maxInvestors = 10000;

    // Maximum Investment per User
    uint256 public maxInvestment = 10000 * 10 ** 18; // $10,000

    // Minimum Investment per User
    uint256 public minInvestment = 10 * 10 ** 18; // $10

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

    // Mapping to track the owner of each vested token
    mapping(address => mapping(uint256 => address)) public vestedTokenOwners;

    constructor(address _owner, address _LOIContract) {
        LOIContract = _LOIContract;
        investorCount = 0;
        preIEOActive = false; // Initialize preIEOActive variable
        transferOwnership(_owner);
    }

    modifier isPreIEOActive() {
        if (!preIEOActive)
            revert LOINotActive();
        _;
    }

   modifier isWhitelisted() {
    require(whitelist[msg.sender], "Investor not whitelisted");
    _;
}

    modifier onlyOwnerOfVestedTokens(address _investor) {
    require(msg.sender == _investor, "Only owner of vested tokens can call this function");
    _;
}

    modifier isVestingActive(address investor) {
        if (block.timestamp < destroyTime || vestedAmount[investor] == 0)
            revert LOINotActive();
        _;
    }

    modifier refundInvestor() {
    require(msg.sender == owner(), "Only contract owner can refund investor");
    _;
}

// Set the USDT Token Contract Address
function set_USDTContract(address _USDTContract) public onlyOwner {
    require(_USDTContract != address(0), "Invalid USDT contract address");
    USDTContract = IUSDT(_USDTContract);
}

    // Set the LOI Token Contract Address
   function set_LOIContract(address _LOIContract) public onlyOwner {
    require(_LOIContract != address(0), "Invalid contract address");
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

    // Start the Pre-IEO Round
function startPreIEO(uint256 _totalTokens, uint256 _destroyTime) external onlyOwner {
    require(!preIEOActive, "Pre-IEO already active");
    require(_totalTokens > 0, "Invalid total tokens");
    require(_destroyTime > block.timestamp, "Invalid destroy time");

    // Check if the contract has sufficient USDT balance
    uint256 requiredUSDT = SafeMath.mul(_totalTokens, tokenPrice);
    require(IUSDT(USDTContract).balanceOf(address(this)) >= requiredUSDT, "Insufficient USDT balance");

    // Validate the parameters
    require(_totalTokens > 0, "Total tokens must be greater than 0");
    require(_destroyTime > block.timestamp, "Destroy time must be in the future");

    totalTokens = _totalTokens;
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
    uint256 amount = IUSDT(USDTContract).balanceOf(msg.sender);
    require(amount >= minInvestment, "Amount is less than the minimum investment amount");
    require(amount <= maxInvestment, "Amount is more than the maximum investment amount");

    // Adjust the precision to match the number of decimal places in tokenPrice
    uint256 precision = 10**18;
    uint256 tokensToBuy = amount.mul(precision).div(tokenPrice);

    // Apply tire-based bonus
    uint256 bonusPercentage;
    if (amount >= 10 * 10 ** 18 && amount <= 999 * 10 ** 18) {
        bonusPercentage = 42;
    } else if (amount >= 1000 * 10 ** 18 && amount <= 4999 * 10 ** 18) {
        bonusPercentage = 62;
    } else if (amount >= 5000 * 10 ** 18 && amount <= 10000 * 10 ** 18) {
        bonusPercentage = 82;
    } else {
        bonusPercentage = 0;
    }

    // Calculate bonus tokens
    uint256 bonusTokens = tokensToBuy.mul(bonusPercentage).div(100);

    // Ensure that the number of tokens to buy is within the available limit
    require(tokensSold.add(tokensToBuy.add(bonusTokens)) <= totalTokens, "Not enough tokens left for sale or arithmetic overflow");

    // Update the number of tokens sold and the investor's vested amount
    tokensSold = tokensSold.add(tokensToBuy).add(bonusTokens);
    if (vestedAmount[msg.sender] == 0) {
        investorCount = investorCount.add(1);
    }
    vestedAmount[msg.sender] = vestedAmount[msg.sender].add(tokensToBuy.add(bonusTokens).div(2));
    vestingStart[msg.sender] = block.timestamp.add(vestingCliff);

    // Track the owner of the vested tokens
    uint256 tokenId = investorCount.mul(2).sub(1);
    vestedTokenOwners[msg.sender][tokenId] = msg.sender;
    vestedTokenOwners[msg.sender][tokenId.add(1)] = owner();

    // Transfer USDT from the investor to the contract
    require(USDTContract.transferFrom(msg.sender, address(this), amount), "Failed to transfer USDT");

    // Transfer tokens to the investor
    require(IERC20(LOIContract).transfer(msg.sender, tokensToBuy.add(bonusTokens)), "Failed to transfer tokens");

    // Emit event
    emit TokensPurchased(msg.sender, tokensToBuy.add(bonusTokens));
    emit VestingStarted(msg.sender, vestedAmount[msg.sender], vestingStart[msg.sender]);
}


// Withdraw USDT from Contract
  function withdrawUSDT() external onlyOwner {
    address payable ownerAddress = payable(owner());
    USDTContract.transfer(ownerAddress, IUSDT(USDTContract).balanceOf(address(this)));
}

// Withdraw Tokens from Contract
function withdrawTokens(uint256 _amount) external onlyOwner isPreIEOActive {
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
    require(vestingStart[msg.sender] == 0, "Vesting already started for investor");

    // Set vesting start time for the calling investor
    vestingStart[msg.sender] = block.timestamp;

    // Set vesting end time based on vesting period
    vestingEnd[msg.sender] = vestingStart[msg.sender].add(vestingPeriod);

    // Initialize vestedAmount for the investor to maximum tokens purchased in Pre-IEO round
    vestedAmount[msg.sender] = maxInvestment.div(tokenPrice);

    emit VestingStarted(msg.sender, vestedAmount[msg.sender], vestingStart[msg.sender]);
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
    return vestedAmount[msg.sender];
}

 // Unlock Vested Tokens for a Specific Investor
function unlockTokens() external {
    require(block.timestamp >= vestingEnd[msg.sender], "Vesting period not over yet");

    uint256 tokensToUnlock = calculateVestedTokens(msg.sender);

    require(tokensToUnlock > 0, "No vested tokens to unlock");

    vestedAmount[msg.sender] = vestedAmount[msg.sender].sub(tokensToUnlock);

    // Transfer Tokens to Investor
    uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
    require(LOIBalance >= tokensToUnlock, "Insufficient LOI tokens in contract");
    require(IERC20(LOIContract).transfer(msg.sender, tokensToUnlock), "Token transfer failed");
}

 // Withdraw Vested Tokens for a Specific Investor
function withdrawVestedTokens() external isVestingActive(msg.sender) {
    require(block.timestamp >= vestingEnd[msg.sender], "Vesting period not over yet");

    uint256 tokensToWithdraw = calculateVestedTokens(msg.sender);
    require(tokensToWithdraw > 0, "No vested tokens to withdraw");

    vestedAmount[msg.sender] = vestedAmount[msg.sender].sub(tokensToWithdraw);

    // Transfer Tokens to Investor
    uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
    require(LOIBalance >= tokensToWithdraw, "Insufficient LOI tokens in contract");
    require(IERC20(LOIContract).transfer(msg.sender, tokensToWithdraw), "Token transfer failed");
}

// Get the number of tokens that have vested for an investor
    function getVestedTokens(address _investor) external view returns (uint256) {
    return vestedAmount[_investor];
}

 // Refund USDT or Tokens to Investor
function refundInvestorVested(address payable _investor, uint256 _USDTAmount, uint256 _tokenAmount) external onlyOwner {
    require(_investor != address(0), "Invalid investor address");

    // Refund Tokens to Investor
    if (_tokenAmount > 0) {
        require(IERC20(LOIContract).balanceOf(address(this)) >= _tokenAmount, "Insufficient LOI token balance in contract");
        require(vestedAmount[_investor] >= _tokenAmount, "Insufficient vested LOI tokens for the investor");

        vestedAmount[_investor] = vestedAmount[_investor].sub(_tokenAmount);

        require(IERC20(LOIContract).transfer(_investor, _tokenAmount), "Token transfer failed");

        // Emit event for token refund
        emit TokensRefunded(_investor, _tokenAmount);
    }

    // Refund USDT to Investor
    if (_USDTAmount > 0) {
        require(address(this).balance >= _USDTAmount, "Insufficient ether balance in contract");
        require(IUSDT(USDTContract).balanceOf(address(this)) >= _USDTAmount, "Insufficient USDT balance in contract");

        // Transfer USDT from the contract to the investor
        require(IUSDT(USDTContract).transfer(_investor, _USDTAmount), "USDT transfer failed");

        // Emit event for USDT refund
        emit USDTRefunded(_investor, _USDTAmount);
    }
}

// Event for token refund
event TokensRefunded(address indexed investor, uint256 amount);

// Event for USDT refund
event USDTRefunded(address indexed investor, uint256 amount);

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
