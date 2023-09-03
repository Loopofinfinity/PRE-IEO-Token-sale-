// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LOITOKENSALE is Context, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Custom error for when the LOI token is not active
    error LOINotActive();

    // LOI Token Contract Address
    address public LOIContract;

    // Maximum Number of Investors
    uint256 public maxInvestors = 100000;

    // Address of the MATIC/USD price feed contract on Coingecko (replace with the actual address)
    address public constant MATIC_USD_PRICE_FEED = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0;

    // Maximum Investment per User in USD
    uint256 public maxInvestment = 10000; // $10,000

    // Minimum Investment per User in USD
    uint256 public minInvestmentUSD = 10; // $10

    // Maximum Investment per User in MATIC tokens (calculated based on the price feed)
    uint256 public maxInvestmentMATIC;

    // Minimum Investment per User in MATIC tokens (calculated based on the price feed)
    uint256 public minInvestmentMATIC;

    // Total Tokens for Pre-sale
    uint256 public totalTokens;

    // Tokens Sold in Pre-sale
    uint256 public tokensSold;

    // Pre-IEO Round Status
    bool public preIEOActive;

    // Time-lock mechanism
    uint256 public destroyTime;

    uint256 public heWantsToBuy;

    // Token price
    uint256 public tokenPrice; // $0.008 per token, in USD

    // Investor counter
    uint256 public investorCount;

    // Events
    event TokensPurchased(address indexed investor, uint256 amount);

    constructor(address _owner, address _LOIContract) {
        LOIContract = _LOIContract;
        investorCount = 0;
        preIEOActive = false;
        transferOwnership(_owner);
    }

    modifier isLOIActive() {
        require(preIEOActive, "LOI token is not active");
        _;
    }

    // Set the LOI Token Contract Address
    function set_LOIContract(address _LOIContract) external onlyOwner {
        LOIContract = _LOIContract;
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

    // Set the Minimum Investment Per User 
    function setMinInvestment(uint256 _minInvestment) external onlyOwner {
        require(_minInvestment > 0, "Invalid min investment amount");
        minInvestmentUSD = _minInvestment;
    }

    // Function to fetch the current price of MATIC in USD from Coingecko
    function fetchMATICPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(MATIC_USD_PRICE_FEED);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid MATIC price");
        return uint256(price);
    }

    // Function to set the max and min investment in MATIC tokens based on the current price
    function updateInvestmentLimits() public {
        uint256 maticPrice = fetchMATICPrice();

        maxInvestmentMATIC = maxInvestment * 1e18 / maticPrice;
        minInvestmentMATIC = minInvestmentUSD * 1e18 / maticPrice;
    }

    // Function to start the pre-IEO round
    function startPreIEO(uint256 _totalTokens, uint256 _destroyTime) external onlyOwner {
        require(!preIEOActive, "Pre-IEO already active");
        require(_totalTokens > 0, "Invalid total tokens");
        destroyTime = block.timestamp + _destroyTime;

        updateInvestmentLimits();

        totalTokens = _totalTokens;
        tokensSold = 0;
        preIEOActive = true;
    }

    // Stop the Pre-IEO Round
    function stopPreIEO() external onlyOwner {
        require(preIEOActive, "Pre-IEO not active");

        preIEOActive = false;
    }

    function convertLOItoMatic() internal returns (uint256) {
        uint256 maticPrice = fetchMATICPrice();
        tokenPrice = SafeMath.mul(800000, 1e18).div(maticPrice);
        return tokenPrice;
    }

    // Purchase Tokens in Pre-IEO Round with Matic
    function purchaseTokens() external payable nonReentrant {
    require(preIEOActive, "Pre-IEO not active");

    convertLOItoMatic();

    // Calculate tokens to buy with rounding
    uint256 tokensToBuy = (msg.value * 1e18 + tokenPrice / 2) / tokenPrice;

    uint256 bonusPercentage;
    if (msg.value >= 10 * tokenPrice && msg.value <= 999 * tokenPrice) {
        bonusPercentage = 42;
    } else if (msg.value >= 1000 * tokenPrice && msg.value <= 4999 * tokenPrice) {
        bonusPercentage = 62;
    } else if (msg.value >= 5000 * tokenPrice && msg.value <= 10000 * tokenPrice) {
        bonusPercentage = 82;
    } else {
        bonusPercentage = 0;
    }

    uint256 bonusTokens = tokensToBuy.mul(bonusPercentage).div(100);

    // Calculate total tokens to buy with rounding
    uint256 totalTokensToBuy = tokensToBuy.add(bonusTokens);

    require(totalTokensToBuy > 0, "No tokens to buy");
    require(tokensSold.add(totalTokensToBuy) <= totalTokens, "Not enough tokens left for sale");

    tokensSold = tokensSold.add(totalTokensToBuy);

    // Increment investor count
    investorCount = investorCount.add(1);

    // Transfer purchased tokens to the investor's wallet
    transferTokensToInvestor(_msgSender(), totalTokensToBuy);

    // Emit event for tokens purchased
    emit TokensPurchased(_msgSender(), totalTokensToBuy);
}

    // Withdraw Matic from Contract
    function withdrawMatic() external onlyOwner {
        address payable ownerAddress = payable(owner());
        ownerAddress.transfer(address(this).balance);
    }

    // Withdraw unsold LOI tokens from Contract
    function withdrawUnsoldLOITokens() external onlyOwner {
    uint256 unsoldTokens = totalTokens - tokensSold;
    require(unsoldTokens > 0, "No unsold tokens available");

    require(IERC20(LOIContract).transfer(owner(), unsoldTokens), "Token transfer failed");
}

    // Get the Balance of LOI Tokens in Contract
    function getLOIBalance() external view returns (uint256) {
        return IERC20(LOIContract).balanceOf(address(this));
    }

    // Get the Matic Balance of Contract
    function getMaticBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Function to destroy contract
        function destroyContract() external onlyOwner nonReentrant {
        uint256 LOIBalance = IERC20(LOIContract).balanceOf(address(this));
        require(LOIBalance > 0, "No LOI tokens in contract");

        require(destroyTime != 0, "Contract has already been destroyed");

        require(block.timestamp >= destroyTime, "Contract cannot be destroyed yet");

        require(IERC20(LOIContract).transfer(owner(), LOIBalance), "Token transfer failed");

        uint256 MaticBalance = address(this).balance;
        if (MaticBalance > 0) {
            require(payable(owner()).send(MaticBalance), "Matic transfer failed");
        }

        uint256 etherBalance = address(this).balance;
        if (etherBalance > 0) {
            payable(owner()).transfer(etherBalance);
        }

        destroyTime = 0;
    }

    function getSoldTokens() public view returns (uint256) {
        return tokensSold;
    }

    // Transfer tokens from contract to investor's wallet
    function transferTokensToInvestor(address investor, uint256 tokenAmount) internal {
        require(IERC20(LOIContract).transfer(investor, tokenAmount), "Token transfer failed");
    }

    // View function to check if the pre-IEO state is active
    function isPreIEOActive() external view returns (bool) {
        return preIEOActive;
    }

    // Fallback Function
    fallback() external payable {}

    // Receive Function
    receive() external payable {}
}
