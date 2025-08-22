// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MCO2_Enhanced is ERC20, AccessControl, Pausable, ReentrancyGuard {

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant MAX_SUPPLY = 10_000_000 * 10**18; // 10M tokens
    uint256 public constant MINT_RATE = 1_000 * 10**18; // 1,000 per mint


    string private _tokenName;
    string private _tokenSymbol;


    AggregatorV3Interface public priceFeed;
    uint256 public currentPrice; // USD price (scaled)
    uint256 public lastPriceUpdate;
    uint256 public priceUpdateInterval = 86400; // 24h


    mapping(address => bool) private _blacklisted;
    mapping(address => uint256) private _lastTxBlock;
    uint256 public cooldownPeriod = 1; // Blocks


    event MetadataUpdated(string newName, string newSymbol);
    event PriceUpdated(uint256 newPrice);
    event Blacklisted(address indexed account, bool status);
    event BridgeTransfer(address indexed from, uint256 amount);


    modifier onlyOwner() {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not owner");
        _;
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not minter");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!_blacklisted[account], "Account blacklisted");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address priceFeed_
    ) ERC20(name_, symbol_) {
        _tokenName = name_;
        _tokenSymbol = symbol_;

        // Setup roles
        _setupRole(OWNER_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);

        // Initialize price feed
        priceFeed = AggregatorV3Interface(priceFeed_);
        _updatePrice();

        // Initial mint (2M tokens)
        _mint(msg.sender, 2_000_000 * 10**18);
    }


    function mint(address to, uint256 amount) 
        external 
        onlyMinter 
        whenNotPaused 
        notBlacklisted(to)
        cooldownPeriod
        nonReentrant
    {
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply exceeded");
        _mint(to, amount);
    }


    function bridgeBurn(address from, uint256 amount) 
        external 
        onlyRole(BRIDGE_ROLE) 
        nonReentrant
    {
        _burn(from, amount);
        emit BridgeTransfer(from, amount);
    }

    function bridgeMint(address to, uint256 amount) 
        external 
        onlyRole(BRIDGE_ROLE) 
        nonReentrant
    {
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply exceeded");
        _mint(to, amount);
    }


    function updateTokenInfo(string memory newName, string memory newSymbol) 
        external 
        onlyOwner 
    {
        _tokenName = newName;
        _tokenSymbol = newSymbol;
        emit MetadataUpdated(newName, newSymbol);
    }


    function _updatePrice() internal {
        (, int256 price,,,) = priceFeed.latestRoundData();
        currentPrice = uint256(price) * 10**10; // Adjust decimals
        lastPriceUpdate = block.timestamp;
        emit PriceUpdated(currentPrice);
    }

    function updatePriceManually(uint256 newPrice) external onlyOwner {
        require(block.timestamp > lastPriceUpdate + priceUpdateInterval, "Too soon");
        currentPrice = newPrice;
        lastPriceUpdate = block.timestamp;
        emit PriceUpdated(newPrice);
    }


    function blacklist(address account, bool status) external onlyOwner {
        _blacklisted[account] = status;
        emit Blacklisted(account, status);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function transfer(address recipient, uint256 amount)

        public 
        override 
        whenNotPaused 
        notBlacklisted(msg.sender)
        notBlacklisted(recipient)
        returns (bool) 
    {
        _checkCooldown(msg.sender);
        return super.transfer(recipient, amount);
        emit Transfer(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) 
        public 
        override 
        whenNotPaused 
        notBlacklisted(sender)
        notBlacklisted(recipient)
        returns (bool) 
    {
        _checkCooldown(sender);
        return super.transferFrom(sender, recipient, amount);
    }

    function _checkCooldown(address account) internal {
        require(_lastTxBlock[account] + cooldownPeriod < block.number, "Cooldown active");
        _lastTxBlock[account] = block.number;
    }


    function name() public view override returns (string memory) {
        return _tokenName;
    }

    function symbol() public view override returns (string memory) {
        return _tokenSymbol;
    }

    function isBlacklisted(address account) public view returns (bool) {
        return _blacklisted[account];
    }

    function getTokenInfo() external view returns (
        string memory name_,
        string memory symbol_,
        uint256 supply,
        uint256 price,
        uint256 lastPriceUpdate_
    ) {
        return (
            _tokenName,
            _tokenSymbol,
            totalSupply(),
            currentPrice,
            lastPriceUpdate
        );
    }
}
