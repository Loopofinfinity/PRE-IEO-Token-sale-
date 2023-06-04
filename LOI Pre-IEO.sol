// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUSDT {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract LOIPreIEO is Ownable {
    using SafeMath for uint256;

    // LOI Token Contract Address
    address public LOIContract;

// USDT Token Contract Address
address public USDTContract;

    // Whitelisted Investors
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public vestedAmount; // new variable for vested tokens
    mapping(address => uint256) public vestingStart; // new variable for vesting start time


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
    uint256 public vestingPeriod = 90 days; // 3 months

    // Vesting cliff duration in seconds
    uint256 public constant vestingCliff = 30 days; // 1 month
    
     // Token price
    uint256 public tokenPrice = 8000000000000000; // $0.0080 per token, in USDT

    // Investor counter
    uint256 public investorCount;

    // Events
    event TokensPurchased(address indexed investor, uint256 amount);
    event VestingStarted(address indexed investor, uint256 vestedAmount, uint256 vestingStart);

    // Mapping to track the owner of each vested token
mapping(address => mapping(uint256 => address)) public vestedTokenOwners;

// Contructor 
  constructor(address _owner, address _LOIContract) {
    LOIContract = _LOIContract;
    investorCount = 0;
    transferOwnership(_owner);
}

    modifier isPreIEOActive() {
    require(preIEOActive, "Pre-IEO not active");
    _;
}
    modifier isWhitelisted() {
    require(whitelist[msg.sender], "Investor is not whitelisted");
    _;
}

 modifier onlyOwnerOfVestedTokens(address _investor) {
        require(msg.sender == _investor, "Only owner of vested tokens can access them");
        _;
    }

    modifier isVestingActive(address investor) {
    require(block.timestamp >= destroyTime, "Vesting not started yet");
    require(vestedAmount[investor] > 0, "Investor has no vested tokens");
    _;
}

// Set the USDT Token Contract Address
function setUSDTContract(address _USDTContract) external onlyOwner {
    require(_USDTContract != address(0), "Invalid USDT contract address");
    USDTContract = _USDTContract;
}

    // Set the LOI Token Contract Address
    function setLOIContract(address _LOIContract) external onlyOwner {
    require(_LOIContract != address(0), "Invalid LOI contract address");
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
    whitelist[_investor] = false;
}

    // Set the Maximum Number of Investors
    function setMaxInvestors(uint256 _maxInvestors) external onlyOwner {
        maxInvestors = _maxInvestors;
    }

    // Set the Maximum Investment per User
    function setMaxInvestment(uint256 _maxInvestment) external onlyOwner {
        maxInvestment = _maxInvestment;
    }

    // Set the Minimum Investment per User
    function setMinInvestment(uint256 _minInvestment) external onlyOwner {
        minInvestment = _minInvestment;
    }

    // Start the Pre-IEO Round
function startPreIEO(uint256 _totalTokens, uint256 _destroyTime) external onlyOwner {
    require(!preIEOActive, "Pre-IEO already active");
    require(_totalTokens > 0, "Invalid total tokens");
    require(_destroyTime > block.timestamp, "Invalid destroy time");

    // Convert _totalTokens to a BigNumber object
    uint256 totalTokensBN = _totalTokens;

    totalTokens = totalTokensBN;
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
function purchaseTokens() external isPreIEOActive isWhitelisted {
    require(preIEOActive, "Pre-IEO not active");
    require(whitelist[msg.sender], "Investor not whitelisted");

    uint256 amount = IUSDT(USDTContract).balanceOf(msg.sender);
    require(amount >= minInvestment, "Amount is less than the minimum investment amount");
    require(amount <= maxInvestment, "Amount is more than the maximum investment amount");

    // Calculate the number of tokens based on the token price
    uint256 tokensToBuy = amount.div(tokenPrice);

    // Ensure that the number of tokens to buy is within the available limit
    require(tokensSold.add(tokensToBuy) <= totalTokens, "Not enough tokens left for sale");

    // Transfer USDT from the investor to the contract
    require(IUSDT(USDTContract).transferFrom(msg.sender, address(this), amount), "Failed to transfer USDT");

    // Transfer tokens to the investor
    require(IERC20(LOIContract).transfer(msg.sender, tokensToBuy), "Failed to transfer tokens");

    // Update the number of tokens sold and the investor's vested amount
    tokensSold = tokensSold.add(tokensToBuy);
    if (vestedAmount[msg.sender] == 0) {
        investorCount = investorCount.add(1);
    }
    vestedAmount[msg.sender] = vestedAmount[msg.sender].add(tokensToBuy.div(2));
    vestingStart[msg.sender] = block.timestamp.add(vestingCliff);

    // Track the owner of the vested tokens
    uint256 tokenId = investorCount.mul(2).sub(1);
    vestedTokenOwners[msg.sender][tokenId] = msg.sender;
    vestedTokenOwners[msg.sender][tokenId.add(1)] = owner();

    // Emit event
    emit TokensPurchased(msg.sender, tokensToBuy);
    emit VestingStarted(msg.sender, vestedAmount[msg.sender], vestingStart[msg.sender]);
}

// Withdraw Ether from Contract
    function withdrawEther() external onlyOwner isPreIEOActive isWhitelisted {
    address payable owner = payable(owner());
    owner.transfer(address(this).balance);
}

// Withdraw Tokens from Contract
    function withdrawTokens(uint256 _amount) external onlyOwner isPreIEOActive isWhitelisted {
    require(block.timestamp >= destroyTime, "Tokens are still locked");
    uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
    require(_amount <= LOIBalance, "Insufficient LOI tokens in contract");
    require(IERC20(LOIContract).transfer(owner(), _amount), "Token transfer failed");
}

// Get the Balance of LOI Tokens in Contract
    function getLOIBalance() external view returns (uint256) {
    return IERC20(LOIContract).balanceOf(address(this));
}

// Get the Ether Balance of Contract
    function getEtherBalance() external view returns (uint256) {
    return address(this).balance;
}

function startVesting() external {
    require(preIEOActive == false, "Pre-IEO still active");

    // set vesting start time for the calling investor
    vestingStart[msg.sender] = block.timestamp;
    // initialize vestedAmount for the investor to maximum tokens purchased in Pre-IEO round
    vestedAmount[msg.sender] = maxInvestment.div(tokenPrice);

    emit VestingStarted(msg.sender, vestedAmount[msg.sender], vestingStart[msg.sender]);
}

function calculateVestedTokens(address investor) public view returns (uint256) {
    require(vestingStart[investor] > 0, "Vesting not started for investor");

    uint256 elapsedTime = block.timestamp.sub(vestingStart[investor]);
    if (elapsedTime < vestingCliff) {
        return 0;
    }
    uint256 vestingDuration = vestingPeriod.sub(vestingCliff);
    uint256 vestedTokens = vestedAmount[investor].mul(elapsedTime.sub(vestingCliff)).div(vestingDuration);

    return vestedTokens;
}

    function getVestedAmount() external view isVestingActive(msg.sender) returns (uint256) {
    return vestedAmount[msg.sender];
}

// Unlock Vested Tokens for a Specific Investor
    function unlockTokens() external {
    require(block.timestamp >= destroyTime, "Vesting period not over yet");
    uint256 tokensToUnlock = vestedAmount[msg.sender];
    require(tokensToUnlock > 0, "No vested tokens to unlock");

    vestedAmount[msg.sender] = 0;

    // Transfer Tokens to Investor
    uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
    require(LOIBalance >= tokensToUnlock, "Insufficient LOI tokens in contract");
    require(IERC20(LOIContract).transfer(msg.sender, tokensToUnlock), "Token transfer failed");
}

    function withdrawVestedTokens() external isVestingActive(msg.sender) {
    uint256 tokensToWithdraw = vestedAmount[msg.sender];
    vestedAmount[msg.sender] = 0;

    // Transfer Tokens to Investor
    uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
    require(LOIBalance >= tokensToWithdraw, "Insufficient LOI tokens in contract");
    require(IERC20(LOIContract).transfer(msg.sender, tokensToWithdraw), "Token transfer failed");
}

// Get the number of tokens that have vested for an investor
    function getVestedTokens(address _investor) external view returns (uint256) {
    return vestedAmount[_investor];
}

// Refund Ether or Tokens to Investor
    function refundInvestor(address payable _investor, uint256 _etherAmount, uint256 _tokenAmount) external onlyOwner isWhitelisted {
    require(_investor != address(0), "Invalid investor address");

    // Refund Ether to Investor
    if (_etherAmount > 0) {
        require(address(this).balance >= _etherAmount, "Insufficient ether balance in contract");
        _investor.transfer(_etherAmount);
    }

    // Refund Tokens to Investor
    if (_tokenAmount > 0) {
        require(IERC20(LOIContract).balanceOf(address(this)) >= _tokenAmount, "Insufficient LOI token balance in contract");
        require(IERC20(LOIContract).transfer(_investor, _tokenAmount), "Token transfer failed");
    }
}
    function destroyContract() external onlyOwner {
    uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
    require(LOIBalance > 0, "No LOI tokens in contract");

    // Check if the destroy time has passed
    require(block.timestamp >= destroyTime, "Contract cannot be destroyed yet");

    // Transfer remaining LOI tokens to owner
    require(IERC20(LOIContract).transfer(owner(), LOIBalance), "Token transfer failed");

    // Transfer any remaining ether to owner
    uint256 etherBalance = address(this).balance;
    require(etherBalance > 0, "No ether in contract");
    payable(owner()).transfer(etherBalance);
}


// Set the destroy time (in seconds since Unix epoch)
    function setDestroyTime(uint256 _destroyTime) external onlyOwner {
    destroyTime = _destroyTime;
}


// Fallback Function
fallback() external payable {}

// Receive Function
receive() external payable {}
}
