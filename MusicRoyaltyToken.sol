// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Music Royalty Token (MRT)
 * @notice Fungible ERC-20 token representing fractional ownership of music streaming royalties.
 *         Holders receive a proportional share of ETH royalties deposited by the artist/administrator.
 */
contract MusicRoyaltyToken {

    // ─────────────────────────────────────────────
    //  ERC-20 State
    // ─────────────────────────────────────────────

    string  public name;
    string  public symbol;
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ─────────────────────────────────────────────
    //  Royalty Distribution State
    // ─────────────────────────────────────────────

    address public owner;
    string  public songTitle;
    uint256 public totalDeposited;

    uint256 private _rewardPerTokenStored;
    uint256 private constant PRECISION = 1e18;

    mapping(address => uint256) private _rewardPerTokenPaid;
    mapping(address => uint256) private _pendingRewards;

    // ─────────────────────────────────────────────
    //  Redemption State
    // ─────────────────────────────────────────────

    uint256 public redemptionReserve;
    bool    public redemptionEnabled;

    // ─────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner_, address indexed spender, uint256 value);
    event RoyaltiesDeposited(address indexed depositor, uint256 amount);
    event RoyaltiesClaimed(address indexed holder, uint256 amount);
    event RedemptionReserveFunded(uint256 amount);
    event TokensRedeemed(address indexed holder, uint256 tokenAmount, uint256 ethPaid);
    event RedemptionToggled(bool enabled);

    // ─────────────────────────────────────────────
    //  Modifiers
    // ─────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "MRT: caller is not the owner");
        _;
    }

    modifier updateReward(address account) {
        _pendingRewards[account] += _earned(account);
        _rewardPerTokenPaid[account] = _rewardPerTokenStored;
        _;
    }

    // ─────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _songTitle,
        uint256 _supply
    ) {
        owner     = msg.sender;
        name      = _name;
        symbol    = _symbol;
        songTitle = _songTitle;

        uint256 mintAmount = _supply * (10 ** decimals);
        totalSupply = mintAmount;
        _balances[msg.sender] = mintAmount;

        emit Transfer(address(0), msg.sender, mintAmount);
    }

    // ─────────────────────────────────────────────
    //  ERC-20 Core
    // ─────────────────────────────────────────────

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount)
        public
        updateReward(msg.sender)
        updateReward(to)
        returns (bool)
    {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner_, address spender) public view returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        updateReward(from)
        updateReward(to)
        returns (bool)
    {
        require(_allowances[from][msg.sender] >= amount, "MRT: insufficient allowance");
        _allowances[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "MRT: transfer from zero address");
        require(to   != address(0), "MRT: transfer to zero address");
        require(_balances[from] >= amount, "MRT: insufficient balance");

        _balances[from] -= amount;
        _balances[to]   += amount;
        emit Transfer(from, to, amount);
    }

    // ─────────────────────────────────────────────
    //  Royalty Distribution
    // ─────────────────────────────────────────────

    /// @notice Deposit ETH royalties into the contract for proportional distribution to all holders.
    function depositRoyalties() external payable onlyOwner {
        require(msg.value > 0, "MRT: deposit must be > 0");
        require(totalSupply > 0, "MRT: no tokens in circulation");

        _rewardPerTokenStored += (msg.value * PRECISION) / totalSupply;
        totalDeposited += msg.value;

        emit RoyaltiesDeposited(msg.sender, msg.value);
    }

    /// @notice Returns the amount of ETH currently claimable by `account`.
    function claimableRoyalties(address account) public view returns (uint256) {
        return _pendingRewards[account] + _earned(account);
    }

    /// @notice Withdraw all accumulated royalties to the caller's wallet.
    function claimRoyalties() external updateReward(msg.sender) {
        uint256 reward = _pendingRewards[msg.sender];
        require(reward > 0, "MRT: nothing to claim");

        _pendingRewards[msg.sender] = 0;

        (bool sent, ) = payable(msg.sender).call{value: reward}("");
        require(sent, "MRT: ETH transfer failed");

        emit RoyaltiesClaimed(msg.sender, reward);
    }

    function _earned(address account) internal view returns (uint256) {
        uint256 delta = _rewardPerTokenStored - _rewardPerTokenPaid[account];
        return (_balances[account] * delta) / PRECISION;
    }

    // ─────────────────────────────────────────────
    //  Redemption
    // ─────────────────────────────────────────────

    /// @notice Fund the redemption reserve with ETH for token buybacks.
    function fundRedemptionReserve() external payable onlyOwner {
        require(msg.value > 0, "MRT: must send ETH");
        redemptionReserve += msg.value;
        emit RedemptionReserveFunded(msg.value);
    }

    /// @notice Open or close the redemption window.
    function toggleRedemption(bool enabled) external onlyOwner {
        redemptionEnabled = enabled;
        emit RedemptionToggled(enabled);
    }

    /// @notice Burn `tokenAmount` tokens in exchange for a proportional share of the redemption reserve.
    function redeemTokens(uint256 tokenAmount)
        external
        updateReward(msg.sender)
    {
        require(redemptionEnabled, "MRT: redemption window is closed");
        require(tokenAmount > 0, "MRT: amount must be > 0");
        require(_balances[msg.sender] >= tokenAmount, "MRT: insufficient balance");
        require(redemptionReserve > 0, "MRT: reserve is empty");

        uint256 payout = (tokenAmount * redemptionReserve) / totalSupply;
        require(payout > 0, "MRT: payout rounds to zero");

        _balances[msg.sender] -= tokenAmount;
        totalSupply            -= tokenAmount;
        redemptionReserve      -= payout;

        emit Transfer(msg.sender, address(0), tokenAmount);

        (bool sent, ) = payable(msg.sender).call{value: payout}("");
        require(sent, "MRT: ETH transfer failed");

        emit TokensRedeemed(msg.sender, tokenAmount, payout);
    }

    // ─────────────────────────────────────────────
    //  Admin
    // ─────────────────────────────────────────────

    /// @notice Transfer contract ownership to a new administrator.
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MRT: zero address");
        owner = newOwner;
    }

    /// @notice Returns the total ETH balance held by the contract.
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {
        require(totalSupply > 0, "MRT: no tokens in circulation");
        _rewardPerTokenStored += (msg.value * PRECISION) / totalSupply;
        totalDeposited += msg.value;
        emit RoyaltiesDeposited(msg.sender, msg.value);
    }
}
