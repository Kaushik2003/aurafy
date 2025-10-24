// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IAuraOracle
 * @notice Interface for reading aura values from AuraOracle contract
 */
interface IAuraOracle {
    function getAura(address vault) external view returns (uint256);
    function getLastUpdateTimestamp(address vault) external view returns (uint256);
}

/**
 * @title ICreatorToken
 * @notice Interface for CreatorToken ERC20 contract operations
 * @dev Defines mint, burn, and transferFrom functions that vault uses to manage token supply
 */
interface ICreatorToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title CreatorVault
 * @notice Core vault contract managing dual collateral (creator + fan) and token lifecycle
 * @dev Implements aura-anchored peg, staged progression, forced contraction, and liquidation
 */
contract CreatorVault is ReentrancyGuard, Pausable, Ownable {
    // ============ Structs ============

    /**
     * @notice Represents a fan's minting position
     * @dev Tracks individual mint transactions for FIFO redemption and pro-rata burns
     */
    struct Position {
        address owner; // Fan who minted
        uint256 qty; // Tokens minted in this position
        uint256 collateral; // CELO deposited (minus fees)
        uint8 stage; // Stage at mint time
        uint256 createdAt; // Timestamp of position creation
    }

    /**
     * @notice Configuration for each stage
     * @dev Defines creator stake requirements and mint capacity per stage
     */
    struct StageConfig {
        uint256 stakeRequired; // Cumulative creator stake needed to unlock this stage
        uint256 mintCap; // Maximum tokens mintable at this stage (cumulative)
    }

    // ============ Constants ============

    /// @notice WAD precision constant (1e18) for fixed-point arithmetic
    uint256 public constant WAD = 1e18;

    // Peg function parameters
    uint256 public constant BASE_PRICE = 1e18; // 1 CELO base price
    uint256 public constant A_REF = 100; // Reference aura value
    uint256 public constant A_MIN = 0; // Minimum aura
    uint256 public constant A_MAX = 200; // Maximum aura
    uint256 public constant P_MIN = 0.3e18; // Minimum peg (0.3 CELO)
    uint256 public constant P_MAX = 3.0e18; // Maximum peg (3.0 CELO)
    uint256 public constant K = 0.5e18; // Peg sensitivity (WAD)

    // Collateralization parameters
    uint256 public constant MIN_CR = 1.5e18; // 150% minimum collateralization ratio
    uint256 public constant LIQ_CR = 1.2e18; // 120% liquidation threshold
    uint256 public constant MINT_FEE = 0.005e18; // 0.5% mint fee (WAD)
    uint256 public constant LIQUIDATION_BOUNTY = 0.01e18; // 1% liquidation bounty (WAD)

    // Time windows
    uint256 public constant FORCED_BURN_GRACE = 24 hours; // Grace period before forced burn
    uint256 public constant ORACLE_UPDATE_COOLDOWN = 6 hours; // Cooldown between oracle updates

    // ============ State Variables ============

    /// @notice Address of the creator who owns this vault
    address public immutable creator;

    /// @notice Address of the associated CreatorToken ERC20 contract
    address public token;

    /// @notice Address of the AuraOracle contract
    address public immutable oracle;

    /// @notice Address of the Treasury contract for fee collection
    address public immutable treasury;

    /// @notice CELO staked by creator to unlock stages
    uint256 public creatorCollateral;

    /// @notice CELO deposited by fans when minting
    uint256 public fanCollateral;

    /// @notice Total CELO collateral (creator + fan)
    uint256 public totalCollateral;

    /// @notice Total supply of tokens minted
    uint256 public totalSupply;

    /// @notice Current stage (0 = not bootstrapped, 1+ = unlocked stages)
    uint8 public stage;

    /// @notice Base capacity for supply cap calculation
    uint256 public baseCap;

    /// @notice Tokens pending forced burn after aura drop
    uint256 public pendingForcedBurn;

    /// @notice Deadline timestamp for forced burn execution
    uint256 public forcedBurnDeadline;

    // ============ Mappings ============

    /// @notice Maps fan address to their array of positions
    mapping(address => Position[]) public positions;

    /// @notice Array of all addresses that have positions (for iteration)
    address[] public positionOwners;

    /// @notice Maps address to boolean indicating if they're in positionOwners array
    mapping(address => bool) private isPositionOwner;

    /// @notice Maps stage number to its configuration
    mapping(uint8 => StageConfig) public stageConfigs;

    // ============ Events ============

    event StageUnlocked(address indexed vault, uint8 stage, uint256 stakeAmount);
    event Minted(
        address indexed vault, address indexed minter, uint256 qty, uint256 collateral, uint8 stage, uint256 peg
    );
    event Redeemed(address indexed vault, address indexed redeemer, uint256 qty, uint256 collateralReturned);
    event SupplyCapShrink(
        address indexed vault, uint256 oldCap, uint256 newCap, uint256 pendingBurn, uint256 graceEndTs
    );
    event ForcedBurnExecuted(address indexed vault, uint256 tokensBurned, uint256 collateralWrittenDown);
    event LiquidationExecuted(
        address indexed vault, address indexed liquidator, uint256 payCELO, uint256 tokensRemoved, uint256 bounty
    );

    // ============ Custom Errors ============

    error InsufficientCollateral();
    error StageNotUnlocked();
    error ExceedsStageCap();
    error ExceedsSupplyCap();
    error HealthTooLow();
    error NotLiquidatable();
    error GracePeriodActive();
    error Unauthorized();
    error InsufficientPayment();
    error InsufficientLiquidation();

    // ============ Constructor ============

    /**
     * @notice Initialize a new CreatorVault
     * @param _creator Address of the creator
     * @param _token Address of the CreatorToken contract
     * @param _oracle Address of the AuraOracle contract
     * @param _treasury Address of the Treasury contract
     * @param _baseCap Base capacity for supply cap calculation
     * @param initialOwner Address that will own the contract (for pausable/admin functions)
     */
    constructor(
        address _creator,
        address _token,
        address _oracle,
        address _treasury,
        uint256 _baseCap,
        address initialOwner
    ) Ownable(initialOwner) {
        creator = _creator;
        token = _token;
        oracle = _oracle;
        treasury = _treasury;
        baseCap = _baseCap;

        // Initialize with default values
        stage = 0;
        totalSupply = 0;
    }

    // ============ Mathematical Helper Functions ============

    /**
     * @notice Safe WAD multiplication: (x * y) / WAD
     * @dev Prevents overflow and maintains precision
     * @param x First operand (in WAD)
     * @param y Second operand (in WAD)
     * @return Result in WAD
     */
    function wadMul(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / WAD;
    }

    /**
     * @notice Safe WAD division: (x * WAD) / y
     * @dev Prevents division by zero and maintains precision
     * @param x Numerator (in WAD)
     * @param y Denominator (in WAD)
     * @return Result in WAD
     */
    function wadDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        require(y > 0, "Division by zero");
        return (x * WAD) / y;
    }

    // ============ Mathematical Calculation Functions ============

    /**
     * @notice Calculate peg value based on aura using linear interpolation
     * @dev Formula: P(aura) = BASE_PRICE * (1 + K * (aura/A_REF - 1))
     *      Result is clamped between P_MIN and P_MAX
     * @param aura Current aura value (0-200)
     * @return Peg value in WAD (CELO per token)
     */
    function calculatePeg(uint256 aura) internal pure returns (uint256) {
        // Normalize aura: aN = aura / A_REF (in WAD)
        uint256 aN = wadDiv(aura * WAD, A_REF * WAD);

        // Calculate delta: (aN - 1) in WAD
        // Since aN and WAD are both in WAD units, we subtract directly
        int256 delta = int256(aN) - int256(WAD);

        // Calculate K * delta (both in WAD, so we need to divide by WAD)
        int256 kDelta = (int256(K) * delta) / int256(WAD);

        // Calculate peg: BASE_PRICE * (1 + kDelta)
        // BASE_PRICE is in WAD, kDelta is in WAD, so: BASE_PRICE + BASE_PRICE * kDelta / WAD
        int256 pegRaw = int256(BASE_PRICE) + (int256(BASE_PRICE) * kDelta) / int256(WAD);

        // Clamp to [P_MIN, P_MAX]
        if (pegRaw < int256(P_MIN)) {
            return P_MIN;
        }
        if (pegRaw > int256(P_MAX)) {
            return P_MAX;
        }

        return uint256(pegRaw);
    }

    /**
     * @notice Calculate supply cap based on aura with sensitivity parameter
     * @dev Formula: SupplyCap(aura) = BaseCap * (1 + s * (aura - A_REF) / A_REF)
     *      Result is clamped between BaseCap * 0.25 and BaseCap * 4
     * @param aura Current aura value (0-200)
     * @return Supply cap in token units
     */
    function calculateSupplyCap(uint256 aura) internal view returns (uint256) {
        // Sensitivity parameter s = 0.75 (in WAD)
        uint256 s = 0.75e18;

        // Calculate (aura - A_REF) - can be negative
        int256 auraDelta = int256(aura) - int256(A_REF);

        // Calculate s * (aura - A_REF) / A_REF (in WAD)
        int256 scaleFactor = (int256(s) * auraDelta) / int256(A_REF);

        // Calculate SupplyCap = BaseCap * (1 + scaleFactor)
        // BaseCap is in token units, scaleFactor is in WAD
        int256 supplyCap = int256(baseCap) + (int256(baseCap) * scaleFactor) / int256(WAD);

        // Clamp to [BaseCap * 0.25, BaseCap * 4]
        uint256 minCap = baseCap / 4; // 0.25 * baseCap
        uint256 maxCap = baseCap * 4;

        if (supplyCap < int256(minCap)) {
            return minCap;
        }
        if (supplyCap > int256(maxCap)) {
            return maxCap;
        }

        return uint256(supplyCap);
    }

    /**
     * @notice Get current aura from oracle contract
     * @dev Reads aura dynamically from AuraOracle - single source of truth
     * @return Current aura value for this vault
     */
    function getCurrentAura() public view returns (uint256) {
        return IAuraOracle(oracle).getAura(address(this));
    }

    /**
     * @notice Get current peg based on current aura from oracle
     * @dev Calculates peg dynamically using latest oracle aura value
     * @return Current peg value in WAD
     */
    function getPeg() public view returns (uint256) {
        uint256 aura = getCurrentAura();
        return calculatePeg(aura);
    }

    /**
     * @notice Calculate current health (collateralization ratio) of the vault
     * @dev Formula: Health = totalCollateral / (totalSupply * peg)
     *      Returns WAD-scaled ratio (1.5e18 = 150%)
     * @return Health ratio in WAD (e.g., 1.5e18 = 150% collateralized)
     */
    function calculateHealth() internal view returns (uint256) {
        // If no supply, vault is infinitely healthy
        if (totalSupply == 0) {
            return type(uint256).max;
        }

        // Get current peg dynamically from oracle
        uint256 currentPeg = getPeg();

        // Calculate denominator: totalSupply * peg
        // totalSupply is in token units, peg is in WAD (CELO per token)
        // Result is in CELO (WAD units)
        uint256 denominator = wadMul(totalSupply, currentPeg);

        // Calculate health: totalCollateral / denominator
        // Both are in CELO (WAD units), result is a ratio in WAD
        return wadDiv(totalCollateral, denominator);
    }

    /**
     * @notice Calculate required collateral for minting a given quantity of tokens
     * @dev Formula: requiredCollateral = qty * peg * MIN_CR
     * @param qty Quantity of tokens to mint
     * @return Required collateral in CELO (WAD units)
     */
    function calculateRequiredCollateral(uint256 qty) internal view returns (uint256) {
        // Get current peg dynamically from oracle
        uint256 currentPeg = getPeg();

        // qty is in token units, peg is in WAD (CELO per token)
        // qty * peg gives CELO amount in WAD
        uint256 celoAmount = wadMul(qty, currentPeg);

        // Multiply by MIN_CR (which is in WAD, e.g., 1.5e18 = 150%)
        return wadMul(celoAmount, MIN_CR);
    }

    // ============ Admin Functions ============

    /**
     * @notice Set the token address (one-time initialization)
     * @dev Only owner (factory) can set this, and only once
     * @param _token Address of the CreatorToken contract
     */
    function setToken(address _token) external onlyOwner {
        require(token == address(0), "Token already set");
        require(_token != address(0), "Invalid token address");
        token = _token;
    }

    /**
     * @notice Set stage configuration
     * @dev Only owner (factory) can configure stages
     * @param _stage Stage number (0-N)
     * @param _stakeRequired Cumulative creator stake required to unlock this stage
     * @param _mintCap Maximum tokens mintable at this stage (cumulative)
     */
    function setStageConfig(uint8 _stage, uint256 _stakeRequired, uint256 _mintCap) external onlyOwner {
        stageConfigs[_stage] = StageConfig({stakeRequired: _stakeRequired, mintCap: _mintCap});
    }

    /**
     * @notice Pause the vault to prevent minting, redemption, and liquidation
     * @dev Only owner (factory) can pause. Used for emergency stops.
     *      Requirements: 9.1, 9.5
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the vault to resume normal operations
     * @dev Only owner (factory) can unpause.
     *      Requirements: 9.1, 9.5
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ Creator Functions ============

    /**
     * @notice Bootstrap creator stake to unlock stage 1
     * @dev Creator deposits initial CELO collateral. If sufficient for stage 1, stage is unlocked.
     *      Requirements: 2.1, 2.2
     */
    function bootstrapCreatorStake() external payable {
        if (msg.sender != creator) {
            revert Unauthorized();
        }
        if (msg.value == 0) {
            revert InsufficientPayment();
        }

        // Update creator collateral
        creatorCollateral += msg.value;
        totalCollateral += msg.value;

        // Check if we can unlock stage 1
        if (stage == 0 && creatorCollateral >= stageConfigs[1].stakeRequired) {
            stage = 1;
            emit StageUnlocked(address(this), 1, creatorCollateral);
        }
    }

    /**
     * @notice Unlock the next stage by depositing additional creator collateral
     * @dev Creator must deposit enough to meet cumulative stake requirement for next stage.
     *      Can only increment stage by 1 at a time.
     *      Requirements: 2.3, 2.4, 2.5
     */
    function unlockStage() external payable {
        if (msg.sender != creator) {
            revert Unauthorized();
        }
        if (msg.value == 0) {
            revert InsufficientPayment();
        }
        if (stage == 0) {
            revert StageNotUnlocked();
        }

        // Calculate next stage
        uint8 nextStage = stage + 1;

        // Update collateral first
        creatorCollateral += msg.value;
        totalCollateral += msg.value;

        // Verify we have enough for the next stage
        if (creatorCollateral < stageConfigs[nextStage].stakeRequired) {
            revert InsufficientCollateral();
        }

        // Unlock the next stage
        stage = nextStage;
        emit StageUnlocked(address(this), nextStage, creatorCollateral);
    }

    // ============ Fan Functions ============

    /**
     * @notice Mint creator tokens by depositing CELO collateral
     * @dev Fans deposit CELO to mint tokens. Collateral must meet MIN_CR requirement plus fees.
     *      Creates a Position record for FIFO redemption tracking.
     *      Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 9.1
     * @param qty Quantity of tokens to mint
     */
    function mintTokens(uint256 qty) external payable nonReentrant whenNotPaused {
        // Validate stage is unlocked
        if (stage == 0) {
            revert StageNotUnlocked();
        }

        // Calculate required collateral: qty * peg * MIN_CR
        uint256 requiredCollateral = calculateRequiredCollateral(qty);

        // Calculate fee: requiredCollateral * MINT_FEE / WAD
        uint256 fee = wadMul(requiredCollateral, MINT_FEE);

        // Verify msg.value is sufficient
        if (msg.value < requiredCollateral + fee) {
            revert InsufficientCollateral();
        }

        // Verify totalSupply + qty does not exceed stage mint cap
        if (totalSupply + qty > stageConfigs[stage].mintCap) {
            revert ExceedsStageCap();
        }

        // Calculate current supply cap based on current aura from oracle
        uint256 aura = getCurrentAura();
        uint256 currentSupplyCap = calculateSupplyCap(aura);

        // Verify totalSupply + qty does not exceed supply cap
        if (totalSupply + qty > currentSupplyCap) {
            revert ExceedsSupplyCap();
        }

        // Transfer fee to treasury
        (bool feeSuccess,) = treasury.call{value: fee}(abi.encodeWithSignature("collectFee()"));
        require(feeSuccess, "Fee transfer failed");

        // Calculate actual collateral (msg.value minus fee)
        uint256 actualCollateral = msg.value - fee;

        // Create new Position
        Position memory newPosition = Position({
            owner: msg.sender, qty: qty, collateral: actualCollateral, stage: stage, createdAt: block.timestamp
        });

        // Add position to positions[msg.sender] array
        positions[msg.sender].push(newPosition);

        // If first position for user, add to positionOwners array
        if (!isPositionOwner[msg.sender]) {
            positionOwners.push(msg.sender);
            isPositionOwner[msg.sender] = true;
        }

        // Update fanCollateral and totalCollateral
        fanCollateral += actualCollateral;
        totalCollateral += actualCollateral;

        // Mint tokens to fan
        ICreatorToken(token).mint(msg.sender, qty);

        // Update totalSupply
        totalSupply += qty;

        // Verify health is still above MIN_CR
        uint256 health = calculateHealth();
        if (health < MIN_CR) {
            revert HealthTooLow();
        }

        // Emit Minted event with current peg
        uint256 currentPeg = getPeg();
        emit Minted(address(this), msg.sender, qty, actualCollateral, stage, currentPeg);
    }

    /**
     * @notice Redeem tokens for CELO collateral using FIFO position accounting
     * @dev Fans burn tokens to recover their collateral proportionally from their positions.
     *      Positions are processed in FIFO order. Health must remain above MIN_CR after redemption.
     *      Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 9.1
     * @param qty Quantity of tokens to redeem
     */
    function redeemTokens(uint256 qty) external nonReentrant whenNotPaused {
        if (qty == 0) {
            revert InsufficientPayment();
        }

        // Transfer tokens from msg.sender to this contract
        ICreatorToken(token).transferFrom(msg.sender, address(this), qty);

        // Initialize tracking variables
        uint256 collateralToReturn = 0;
        uint256 qtyRemaining = qty;

        // Iterate through positions[msg.sender] array in FIFO order
        Position[] storage userPositions = positions[msg.sender];
        uint256 positionCount = userPositions.length;

        for (uint256 i = 0; i < positionCount && qtyRemaining > 0; i++) {
            Position storage position = userPositions[i];

            // Skip positions that are already fully redeemed
            if (position.qty == 0) {
                continue;
            }

            // Calculate burnFromPosition = min(position.qty, qtyRemaining)
            uint256 burnFromPosition = position.qty < qtyRemaining ? position.qty : qtyRemaining;

            // Calculate collateralFromPosition = (position.collateral * burnFromPosition) / position.qty
            // Using WAD math for precision
            uint256 collateralFromPosition = (position.collateral * burnFromPosition) / position.qty;

            // Add to total collateral to return
            collateralToReturn += collateralFromPosition;

            // Reduce position.qty and position.collateral by burned amounts
            position.qty -= burnFromPosition;
            position.collateral -= collateralFromPosition;

            // Reduce qtyRemaining
            qtyRemaining -= burnFromPosition;
        }

        // Verify we processed all requested qty
        if (qtyRemaining != 0) {
            revert InsufficientCollateral();
        }

        // Calculate healthAfter = (totalCollateral - collateralToReturn) / ((totalSupply - qty) * peg)
        uint256 newTotalCollateral = totalCollateral - collateralToReturn;
        uint256 newTotalSupply = totalSupply - qty;

        // Get current peg dynamically from oracle
        uint256 currentPeg = getPeg();

        // Calculate health after redemption
        uint256 healthAfter;
        if (newTotalSupply == 0) {
            // If all tokens are redeemed, health is infinite (acceptable)
            healthAfter = type(uint256).max;
        } else {
            // Calculate denominator: newTotalSupply * peg
            uint256 denominator = wadMul(newTotalSupply, currentPeg);
            // Calculate health: newTotalCollateral / denominator
            healthAfter = wadDiv(newTotalCollateral, denominator);
        }

        // Verify healthAfter >= MIN_CR
        if (healthAfter < MIN_CR) {
            revert HealthTooLow();
        }

        // Burn tokens from this contract
        ICreatorToken(token).burn(address(this), qty);

        // Update fanCollateral, totalCollateral, totalSupply
        fanCollateral -= collateralToReturn;
        totalCollateral -= collateralToReturn;
        totalSupply -= qty;

        // Transfer collateralToReturn CELO to msg.sender
        (bool success,) = msg.sender.call{value: collateralToReturn}("");
        require(success, "CELO transfer failed");

        // Emit Redeemed event
        emit Redeemed(address(this), msg.sender, qty, collateralToReturn);
    }

    // ============ Forced Contraction Functions ============

    /**
     * @notice Check if supply exceeds cap and trigger forced burn if needed
     * @dev Anyone can call this to enforce supply cap after aura drops in oracle
     *      Monitors current oracle aura and triggers forced burn with grace period
     *      Requirements: 6.1, 8.5
     */
    function checkAndTriggerForcedBurn() external {
        // Get current aura from oracle
        uint256 aura = getCurrentAura();
        uint256 currentSupplyCap = calculateSupplyCap(aura);

        // Check if supply exceeds cap and no pending burn already
        if (totalSupply > currentSupplyCap && pendingForcedBurn == 0) {
            uint256 oldCap = totalSupply; // Current supply is the "old cap" being exceeded
            uint256 newCap = currentSupplyCap;
            pendingForcedBurn = totalSupply - currentSupplyCap;
            forcedBurnDeadline = block.timestamp + FORCED_BURN_GRACE;
            
            // Emit SupplyCapShrink event
            emit SupplyCapShrink(address(this), oldCap, newCap, pendingForcedBurn, forcedBurnDeadline);
        }
    }

    // ============ Liquidation Functions ============

    /**
     * @notice Liquidate an undercollateralized vault by injecting CELO to burn tokens
     * @dev Liquidators inject CELO to buy down supply and restore vault health.
     *      Liquidator receives a bounty, and creator is penalized.
     *      Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8
     */
    function liquidate() external payable nonReentrant whenNotPaused {
        // Define minimum payment constant (0.01 CELO)
        uint256 minPayCELO = 0.01e18;

        // Calculate current health
        uint256 currentHealth = calculateHealth();

        // Verify currentHealth < LIQ_CR (120%)
        if (currentHealth >= LIQ_CR) {
            revert NotLiquidatable();
        }

        // Verify msg.value >= minPayCELO
        if (msg.value < minPayCELO) {
            revert InsufficientPayment();
        }

        // Get current peg dynamically from oracle
        uint256 currentPeg = getPeg();

        // Calculate tokensToRemove = totalSupply - ((totalCollateral + msg.value) / (peg * MIN_CR / WAD))
        // Rearranging: tokensToRemove = totalSupply - ((totalCollateral + msg.value) * WAD) / (peg * MIN_CR)
        uint256 targetSupply = wadDiv((totalCollateral + msg.value), wadMul(currentPeg, MIN_CR));

        // Verify tokensToRemove > 0
        if (totalSupply <= targetSupply) {
            revert InsufficientLiquidation();
        }

        uint256 tokensToRemove = totalSupply - targetSupply;

        // Burn tokensToRemove proportionally across all positions
        uint256 totalBurned = 0;
        uint256 ownersLength = positionOwners.length;

        for (uint256 i = 0; i < ownersLength; i++) {
            address owner = positionOwners[i];
            Position[] storage userPositions = positions[owner];

            for (uint256 j = 0; j < userPositions.length; j++) {
                Position storage position = userPositions[j];

                if (position.qty == 0) {
                    continue;
                }

                // Calculate pro-rata burn: floor((position.qty * tokensToRemove) / totalSupply)
                uint256 burnFromPosition = (position.qty * tokensToRemove) / totalSupply;

                if (burnFromPosition == 0) {
                    continue;
                }

                // Calculate collateral write-down (collateral is NOT returned, it's written down)
                uint256 collateralWriteDown = (position.collateral * burnFromPosition) / position.qty;

                // Reduce position
                position.qty -= burnFromPosition;
                position.collateral -= collateralWriteDown;

                // Burn tokens from owner
                ICreatorToken(token).burn(owner, burnFromPosition);

                // Accumulate total burned
                totalBurned += burnFromPosition;

                // Update fan collateral and total collateral
                fanCollateral -= collateralWriteDown;
                totalCollateral -= collateralWriteDown;
            }
        }

        // Calculate bounty = (msg.value * LIQUIDATION_BOUNTY) / WAD
        uint256 bounty = wadMul(msg.value, LIQUIDATION_BOUNTY);

        // Transfer bounty to msg.sender immediately
        (bool bountySuccess,) = msg.sender.call{value: bounty}("");
        require(bountySuccess, "Bounty transfer failed");

        // Add (msg.value - bounty) to totalCollateral
        uint256 remainingPayment = msg.value - bounty;
        totalCollateral += remainingPayment;
        fanCollateral += remainingPayment;

        // Calculate creator penalty (10% of creator collateral, capped at 20% of msg.value)
        uint256 penaltyPct = 0.1e18; // 10% in WAD
        uint256 penaltyCap = wadMul(msg.value, 0.2e18); // 20% of msg.value
        uint256 creatorPenalty = wadMul(creatorCollateral, penaltyPct);

        if (creatorPenalty > penaltyCap) {
            creatorPenalty = penaltyCap;
        }

        // Ensure we don't exceed available creator collateral
        if (creatorPenalty > creatorCollateral) {
            creatorPenalty = creatorCollateral;
        }

        // Reduce creatorCollateral by creatorPenalty
        if (creatorPenalty > 0) {
            creatorCollateral -= creatorPenalty;
            totalCollateral -= creatorPenalty;

            // Transfer creatorPenalty to liquidator
            (bool penaltySuccess,) = msg.sender.call{value: creatorPenalty}("");
            require(penaltySuccess, "Penalty transfer failed");
        }

        // Update totalSupply after burns
        totalSupply -= totalBurned;

        // Emit LiquidationExecuted event
        emit LiquidationExecuted(address(this), msg.sender, msg.value, tokensToRemove, bounty);
    }

    // ============ View Functions ============

    /**
     * @notice Get comprehensive vault state information
     * @dev Returns all key vault metrics in a single call for UI/monitoring purposes
     *      Requirements: 8.1
     * @return _creatorCollateral CELO staked by creator
     * @return _fanCollateral CELO deposited by fans
     * @return _totalCollateral Total CELO collateral (creator + fan)
     * @return _totalSupply Total supply of tokens minted
     * @return _peg Current peg value (CELO per token, in WAD) - fetched dynamically from oracle
     * @return _stage Current stage (0 = not bootstrapped, 1+ = unlocked stages)
     * @return health Current health ratio (collateralization ratio in WAD)
     */
    function getVaultState()
        external
        view
        returns (
            uint256 _creatorCollateral,
            uint256 _fanCollateral,
            uint256 _totalCollateral,
            uint256 _totalSupply,
            uint256 _peg,
            uint8 _stage,
            uint256 health
        )
    {
        return (creatorCollateral, fanCollateral, totalCollateral, totalSupply, getPeg(), stage, calculateHealth());
    }

    /**
     * @notice Get a specific position for a fan
     * @dev Returns position details at the specified index in the fan's position array
     *      Requirements: 8.2
     * @param owner Address of the position owner (fan)
     * @param index Index in the owner's positions array
     * @return Position struct containing owner, qty, collateral, stage, and createdAt
     */
    function getPosition(address owner, uint256 index) external view returns (Position memory) {
        if (index >= positions[owner].length) {
            revert InsufficientCollateral();
        }
        return positions[owner][index];
    }

    /**
     * @notice Get the number of positions for a specific fan
     * @dev Returns the length of the positions array for the given owner
     *      Requirements: 8.2
     * @param owner Address of the position owner (fan)
     * @return Number of positions owned by the address
     */
    function getPositionCount(address owner) external view returns (uint256) {
        return positions[owner].length;
    }

    /**
     * @notice Get the current supply cap based on current oracle aura
     * @dev Calculates and returns the maximum allowed token supply using latest aura from oracle
     *      Requirements: 8.3
     * @return Current supply cap in token units
     */
    function getCurrentSupplyCap() external view returns (uint256) {
        uint256 aura = getCurrentAura();
        return calculateSupplyCap(aura);
    }

    // ============ Forced Contraction Functions ============

    /**
     * @notice Execute forced burn of tokens after grace period expires
     * @dev Burns tokens proportionally across all positions when supply exceeds cap after aura drop.
     *      Uses batched processing to manage gas costs with large position sets.
     *      Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8
     * @param maxOwnersToProcess Maximum number of position owners to process in this call (gas limit management)
     */
    function executeForcedBurn(uint256 maxOwnersToProcess) external {
        // Verify grace period has elapsed
        if (block.timestamp < forcedBurnDeadline) {
            revert GracePeriodActive();
        }

        // Verify there is pending forced burn
        if (pendingForcedBurn == 0) {
            revert GracePeriodActive();
        }

        // Initialize tracking variables
        uint256 totalBurned = 0;
        uint256 totalWriteDown = 0;

        // Determine how many owners to process
        uint256 ownersLength = positionOwners.length;
        uint256 ownersToProcess = maxOwnersToProcess < ownersLength ? maxOwnersToProcess : ownersLength;

        // Iterate through positionOwners array up to maxOwnersToProcess limit
        for (uint256 i = 0; i < ownersToProcess; i++) {
            address owner = positionOwners[i];
            Position[] storage userPositions = positions[owner];

            // Iterate through each owner's positions
            for (uint256 j = 0; j < userPositions.length; j++) {
                Position storage position = userPositions[j];

                // Skip positions that are already empty
                if (position.qty == 0) {
                    continue;
                }

                // Calculate burnFromPosition = floor((position.qty * pendingForcedBurn) / totalSupply)
                // This is pro-rata burning based on position's share of total supply
                uint256 burnFromPosition = (position.qty * pendingForcedBurn) / totalSupply;

                // Skip if nothing to burn from this position
                if (burnFromPosition == 0) {
                    continue;
                }

                // Calculate collateralWriteDown = (position.collateral * burnFromPosition) / position.qty
                uint256 collateralWriteDown = (position.collateral * burnFromPosition) / position.qty;

                // Reduce position.qty by burnFromPosition
                position.qty -= burnFromPosition;

                // Reduce position.collateral by collateralWriteDown
                position.collateral -= collateralWriteDown;

                // Burn tokens from owner
                ICreatorToken(token).burn(owner, burnFromPosition);

                // Accumulate totals
                totalBurned += burnFromPosition;
                totalWriteDown += collateralWriteDown;
            }
        }

        // Update totalSupply and totalCollateral after processing
        totalSupply -= totalBurned;
        totalCollateral -= totalWriteDown;
        fanCollateral -= totalWriteDown;

        // Reduce pendingForcedBurn by totalBurned
        pendingForcedBurn -= totalBurned;

        // If pendingForcedBurn == 0, clear forcedBurnDeadline
        if (pendingForcedBurn == 0) {
            forcedBurnDeadline = 0;
        }

        // Emit ForcedBurnExecuted event
        emit ForcedBurnExecuted(address(this), totalBurned, totalWriteDown);
    }
}
