// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Music Royalty Token (MRT)
 * @notice A fungible token representing fractional ownership of music streaming royalties.
 *         Each token entitles the holder to a proportional share of royalty income
 *         deposited by the artist/administrator.
 *
 * Key features:
 *  - Fixed supply ERC-20 token (no inflation post-launch)
 *  - Owner deposits ETH royalties → distributed proportionally to all holders
 *  - Holders can claim accumulated royalties at any time
 *  - Optional redemption: holders can burn tokens for a lump-sum payout
 *
 * Deployment: Remix IDE → Sepolia Testnet
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

    address public owner;           // The artist / administrator
    string  public songTitle;       // Human-readable identifier for the underlying song
    uint256 public totalDeposited;  // Cumulative ETH deposited as royalties (in wei)

    // Tracks how much ETH-per-token had been distributed at the point each
    // address last claimed, allowing incremental claim calculations.
    // Stored as a fixed-point value scaled by PRECISION.
    uint256 private _rewardPerTokenStored;
    uint256 private constant PRECISION = 1e18;

    mapping(address => uint256) private _rewardPerTokenPaid; // snapshot at last claim
    mapping(address => uint256) private _pendingRewards;     // unclaimed ETH (wei)

    // ─────────────────────────────────────────────
    //  Redemption State
    // ─────────────────────────────────────────────

    uint256 public redemptionReserve;   // ETH set aside for token buybacks (wei)
    bool    public redemptionEnabled;   // Owner can open/close redemption window

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

    /**
     * @dev Snapshots the reward-per-token for `account` before any state change
     *      that would affect their balance (transfer, claim, redeem).
     */
    modifier updateReward(address account) {
        _pendingRewards[account] += _earned(account);
        _rewardPerTokenPaid[account] = _rewardPerTokenStored;
        _;
    }

    // ─────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────

    /**
     * @param _name        Token name, e.g. "Royalty – Midnight Drive"
     * @param _symbol      Token symbol, e.g. "MRT-MD"
     * @param _songTitle   Human-readable song identifier
     * @param _supply      Total token supply (in whole tokens; decimals added automatically)
     *
     * Example: deploy with _supply = 1_000_000 to create 1,000,000 MRT,
     * each representing 1/1,000,000 of all future royalty deposits.
     */
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

    /**
     * @notice Artist deposits streaming royalty income into the contract.
     *         The ETH is distributed proportionally to all current token holders.
     * @dev    Any ETH sent here counts as a royalty deposit.
     *         Call this function quarterly (or whenever royalties arrive).
     */
    function depositRoyalties() external payable onlyOwner {
        require(msg.value > 0, "MRT: deposit must be > 0");
        require(totalSupply > 0, "MRT: no tokens in circulation");

        // Increase the global reward-per-token accumulator
        _rewardPerTokenStored += (msg.value * PRECISION) / totalSupply;
        totalDeposited += msg.value;

        emit RoyaltiesDeposited(msg.sender, msg.value);
    }

    /**
     * @notice Returns the amount of ETH currently claimable by `account`.
     */
    function claimableRoyalties(address account) public view returns (uint256) {
        return _pendingRewards[account] + _earned(account);
    }

    /**
     * @notice Holder calls this to withdraw all accumulated royalties to their wallet.
     */
    function claimRoyalties() external updateReward(msg.sender) {
        uint256 reward = _pendingRewards[msg.sender];
        require(reward > 0, "MRT: nothing to claim");

        _pendingRewards[msg.sender] = 0;

        (bool sent, ) = payable(msg.sender).call{value: reward}("");
        require(sent, "MRT: ETH transfer failed");

        emit RoyaltiesClaimed(msg.sender, reward);
    }

    /**
     * @dev Calculates newly earned rewards since the last snapshot for `account`.
     */
    function _earned(address account) internal view returns (uint256) {
        uint256 delta = _rewardPerTokenStored - _rewardPerTokenPaid[account];
        return (_balances[account] * delta) / PRECISION;
    }

    // ─────────────────────────────────────────────
    //  Redemption Mechanism
    // ─────────────────────────────────────────────

    /**
     * @notice Owner funds the redemption reserve (for the buyback programme).
     * @dev    ETH sent here is ring-fenced for redemptions only.
     */
    function fundRedemptionReserve() external payable onlyOwner {
        require(msg.value > 0, "MRT: must send ETH");
        redemptionReserve += msg.value;
        emit RedemptionReserveFunded(msg.value);
    }

    /**
     * @notice Owner opens or closes the redemption window.
     */
    function toggleRedemption(bool enabled) external onlyOwner {
        redemptionEnabled = enabled;
        emit RedemptionToggled(enabled);
    }

    /**
     * @notice Holder burns `tokenAmount` tokens in exchange for a proportional
     *         share of the redemption reserve.
     *
     * ETH received = (tokenAmount / totalSupply) * redemptionReserve
     *
     * @dev Claim outstanding royalties first — burning tokens permanently
     *      forfeits any unclaimed royalty entitlement on those tokens.
     */
    function redeemTokens(uint256 tokenAmount)
        external
        updateReward(msg.sender)
    {
        require(redemptionEnabled, "MRT: redemption window is closed");
        require(tokenAmount > 0, "MRT: amount must be > 0");
        require(_balances[msg.sender] >= tokenAmount, "MRT: insufficient balance");
        require(redemptionReserve > 0, "MRT: reserve is empty");

        // Calculate payout proportional to share of total supply being burned
        uint256 payout = (tokenAmount * redemptionReserve) / totalSupply;
        require(payout > 0, "MRT: payout rounds to zero");

        // Burn the tokens
        _balances[msg.sender] -= tokenAmount;
        totalSupply            -= tokenAmount;
        redemptionReserve      -= payout;

        emit Transfer(msg.sender, address(0), tokenAmount);

        // Send ETH to holder
        (bool sent, ) = payable(msg.sender).call{value: payout}("");
        require(sent, "MRT: ETH transfer failed");

        emit TokensRedeemed(msg.sender, tokenAmount, payout);
    }

    // ─────────────────────────────────────────────
    //  Admin Utilities
    // ─────────────────────────────────────────────

    /**
     * @notice Transfer contract ownership to a new administrator.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MRT: zero address");
        owner = newOwner;
    }

    /**
     * @notice Returns the current ETH balance held by the contract
     *         (royalties awaiting claim + redemption reserve).
     */
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Accept plain ETH transfers as royalty deposits
    receive() external payable {
        require(totalSupply > 0, "MRT: no tokens in circulation");
        _rewardPerTokenStored += (msg.value * PRECISION) / totalSupply;
        totalDeposited += msg.value;
        emit RoyaltiesDeposited(msg.sender, msg.value);
    }
}
