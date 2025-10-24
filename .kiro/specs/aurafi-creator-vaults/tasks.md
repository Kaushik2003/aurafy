# Implementation Plan

## Status Summary
- ✅ Core contracts implemented (CreatorVault, VaultFactory, CreatorToken, AuraOracle, Treasury)
- ✅ Oracle script fully functional
- ✅ Deployment script complete
- ✅ Basic test coverage for all contracts
- ⚠️ Missing: executeForcedBurn function, SupplyCapShrink event, getCurrentSupplyCap view, ICreatorToken interface
- ⚠️ Optional: Comprehensive test coverage (tasks 27-33 marked optional)
- ⚠️ Documentation needs updates to match actual implementation

## Completed Tasks

- [x] 1. Set up project structure and dependencies





  - Initialize Foundry project with OpenZeppelin contracts
  - Configure foundry.toml for Celo network settings (Alfajores testnet)
  - Install OpenZeppelin dependencies: ERC20, Ownable, ReentrancyGuard, Pausable
  - Create directory structure: contracts/, test/, script/, oracle/
  - _Requirements: 9.1, 9.2, 9.3, 9.4_

- [x] 2. Implement Treasury contract





  - Create Treasury.sol with owner-controlled withdrawal function
  - Implement collectFee() payable function to receive fees
  - Add withdraw(address to, uint256 amount) function with onlyOwner modifier
  - Emit TreasuryCollected events for fee collection
  - _Requirements: 3.7, 9.4_

- [x] 3. Implement AuraOracle contract






  - Create AuraOracle.sol with oracle address access control
  - Implement mapping(address => uint256) for vault aura storage
  - Implement mapping(address => string) for IPFS hash storage
  - Implement mapping(address => uint256) for last update timestamp
  - Add pushAura(address vault, uint256 aura, string ipfsHash) function with cooldown check
  - Add getAura(address vault) view function
  - Emit AuraUpdated events with vault, aura, and ipfsHash
  - _Requirements: 5.1, 5.2, 5.6, 8.4_

- [x] 4. Implement CreatorToken ERC20 contract






  - Create CreatorToken.sol extending OpenZeppelin ERC20
  - Add vault address state variable set in constructor
  - Implement mint(address to, uint256 amount) restricted to vault only
  - Implement burn(address from, uint256 amount) restricted to vault only
  - Add onlyVault modifier for access control
  - _Requirements: 1.4, 9.3_

- [x] 5. Implement core CreatorVault data structures and constants






  - Create CreatorVault.sol with Position struct (owner, qty, collateral, stage, createdAt)
  - Define vault state variables: creator, token, oracle, creatorCollateral, fanCollateral, totalCollateral, totalSupply, stage, baseCap, pendingForcedBurn, forcedBurnDeadline
  - Note: aura and peg are NOT stored in vault; they are fetched dynamically from AuraOracle
  - Add mapping(address => Position[]) positions and address[] positionOwners
  - Define WAD constant (1e18) and all protocol constants: BASE_PRICE, A_REF, A_MIN, A_MAX, P_MIN, P_MAX, K, MIN_CR, LIQ_CR, MINT_FEE, LIQUIDATION_BOUNTY, FORCED_BURN_GRACE, ORACLE_UPDATE_COOLDOWN
  - Add StageConfig struct and mapping(uint8 => StageConfig) stageConfigs
  - _Requirements: 1.3, 10.1_

- [x] 6. Implement mathematical calculation functions in CreatorVault





  - Implement calculatePeg(uint256 aura) internal view function using linear interpolation with WAD math
  - Implement calculateSupplyCap(uint256 aura) internal view function with sensitivity parameter and clamping
  - Implement calculateHealth() internal view function as totalCollateral / (totalSupply * peg)
  - Implement calculateRequiredCollateral(uint256 qty) internal view function as qty * peg * MIN_CR
  - Add safe WAD multiplication and division helper functions
  - _Requirements: 10.2, 10.3, 10.4, 10.5, 8.3_

- [x] 7. Implement VaultFactory contract








  - Create VaultFactory.sol with Ownable
  - Add mapping(address => address) creatorToVault registry
  - Implement createVault(string name, string symbol, address creator, uint256 baseCap) function
  - Deploy CreatorToken with name and symbol
  - Deploy CreatorVault with token, oracle, treasury, creator, baseCap
  - Initialize default stage configurations in vault
  - Store vault in registry and emit VaultCreated event
  - Implement setStageConfig(address vault, uint8 stage, uint256 stakeRequired, uint256 mintCap) onlyOwner function
  - _Requirements: 1.1, 1.2, 1.5_

- [x ] 8. Implement creator stake and stage unlock functions









  - Implement bootstrapCreatorStake() payable function in CreatorVault
  - Update creatorCollateral and totalCollateral with msg.value
  - Check if creatorCollateral >= stageConfigs[1].stakeRequired and set stage = 1
  - Emit StageUnlocked event with stage and stake amount
  - Implement unlockStage() payable function
  - Verify creatorCollateral + msg.value >= stageConfigs[stage+1].stakeRequired
  - Increment stage and update collateral
  - Emit StageUnlocked event
  - Add validation to prevent skipping stages
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 9. Implement fan minting with position tracking






  - Implement mintTokens(uint256 qty) payable function with nonReentrant modifier
  - Validate stage > 0, revert with StageNotUnlocked error
  - Fetch current peg using getPeg() which internally fetches aura from oracle
  - Calculate requiredCollateral using calculateRequiredCollateral(qty) with current peg
  - Calculate fee as requiredCollateral * MINT_FEE / WAD
  - Verify msg.value >= requiredCollateral + fee, revert with InsufficientCollateral
  - Verify totalSupply + qty <= stageConfigs[stage].mintCap, revert with ExceedsStageCap
  - Fetch current aura from AuraOracle using IAuraOracle(oracle).getAura(address(this))
  - Calculate currentSupplyCap using calculateSupplyCap(currentAura)
  - Verify totalSupply + qty <= currentSupplyCap, revert with ExceedsSupplyCap
  - Transfer fee to treasury contract
  - Create new Position(msg.sender, qty, msg.value - fee, stage, block.timestamp)
  - Add position to positions[msg.sender] array
  - If first position for user, add msg.sender to positionOwners array
  - Update fanCollateral and totalCollateral
  - Call token.mint(msg.sender, qty)
  - Update totalSupply
  - Verify calculateHealth() >= MIN_CR, revert with HealthTooLow
  - Emit Minted event with minter, qty, collateral, current peg, stage
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 9.1_
-

- [x] 10. Implement token redemption with position-based accounting




  - Implement redeemTokens(uint256 qty) external function with nonReentrant modifier
  - Call token.transferFrom(msg.sender, address(this), qty) to get tokens
  - Initialize collateralToReturn = 0 and qtyRemaining = qty
  - Iterate through positions[msg.sender] array in FIFO order
  - For each position: calculate burnFromPosition = min(position.qty, qtyRemaining)
  - Calculate collateralFromPosition = (position.collateral * burnFromPosition) / position.qty using WAD math
  - Add collateralFromPosition to collateralToReturn
  - Reduce position.qty and position.collateral by burned amounts
  - Reduce qtyRemaining by burnFromPosition
  - Fetch current peg using getPeg() which internally fetches aura from oracle
  - Calculate healthAfter = (totalCollateral - collateralToReturn) / ((totalSupply - qty) * currentPeg)
  - Verify healthAfter >= MIN_CR, revert with HealthTooLow
  - Call token.burn(address(this), qty)
  - Update fanCollateral, totalCollateral, totalSupply
  - Transfer collateralToReturn CELO to msg.sender
  - Emit Redeemed event with redeemer, qty, collateralToReturn
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 9.1_

- [x] 11. Implement oracle aura reading and dynamic peg calculation (PARTIAL - missing executeForcedBurn and SupplyCapShrink event)
  - Add IAuraOracle interface with getAura(address vault) function signature ✓
  - Implement getCurrentAura() public view function that calls IAuraOracle(oracle).getAura(address(this)) ✓
  - Implement getPeg() public view function that fetches current aura and calls calculatePeg(aura) ✓
  - Update calculateHealth() to use getPeg() instead of stored peg ✓
  - Implement checkAndTriggerForcedBurn() external function ✓
  - In checkAndTriggerForcedBurn: fetch current aura, calculate supply cap, check if totalSupply > supplyCap ✓
  - If supply exceeds cap: set pendingForcedBurn = totalSupply - supplyCap, set forcedBurnDeadline = block.timestamp + FORCED_BURN_GRACE ✓
  - Emit SupplyCapShrink event with old cap, new cap, pending burn amount, and deadline ❌ MISSING
  - Remove updateAura() function entirely (no longer needed) ✓
  - Remove onlyOracle modifier from CreatorVault (no longer needed) ✓
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.1, 8.4, 8.5_

- [x] 11b. Complete forced burn implementation






  - Add SupplyCapShrink event to CreatorVault events section
  - Update checkAndTriggerForcedBurn() to emit SupplyCapShrink event when triggered
  - _Requirements: 6.1, 8.5_

- [x] 12. Implement forced contraction execution with batched processing






  - Implement executeForcedBurn(uint256 maxOwnersToProcess) external function
  - Verify block.timestamp >= forcedBurnDeadline, revert with GracePeriodActive
  - Verify pendingForcedBurn > 0
  - Initialize totalBurned = 0 and totalWriteDown = 0
  - Iterate through positionOwners array up to maxOwnersToProcess limit
  - For each owner, iterate through their positions array
  - Calculate burnFromPosition = (position.qty * pendingForcedBurn) / totalSupply using WAD math (floor)
  - Calculate collateralWriteDown = (position.collateral * burnFromPosition) / position.qty
  - Reduce position.qty by burnFromPosition and position.collateral by collateralWriteDown
  - Call token.burn(owner, burnFromPosition)
  - Accumulate totalBurned and totalWriteDown
  - Update totalSupply and totalCollateral after processing
  - Reduce pendingForcedBurn by totalBurned
  - If pendingForcedBurn == 0, clear forcedBurnDeadline
  - Emit ForcedBurnExecuted event with totalBurned and totalWriteDown
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

- [x] 13. Implement liquidation mechanism






  - Implement liquidate() external payable function with nonReentrant modifier
  - Fetch current peg using getPeg() which internally fetches aura from oracle
  - Calculate currentHealth = calculateHealth() (which uses current peg)
  - Verify currentHealth < LIQ_CR, revert with NotLiquidatable
  - Define minPayCELO constant (e.g., 0.01e18 = 0.01 CELO)
  - Verify msg.value >= minPayCELO, revert with InsufficientPayment
  - Calculate tokensToRemove = totalSupply - ((totalCollateral + msg.value) / (currentPeg * MIN_CR / WAD))
  - Verify tokensToRemove > 0, revert with InsufficientLiquidation
  - Burn tokensToRemove proportionally across all positions using similar logic to forced burn
  - Calculate bounty = (msg.value * LIQUIDATION_BOUNTY) / WAD
  - Transfer bounty to msg.sender immediately
  - Add (msg.value - bounty) to totalCollateral
  - Calculate creatorPenalty = min(creatorCollateral * penaltyPct / WAD, penaltyCap)
  - Reduce creatorCollateral by creatorPenalty
  - Transfer creatorPenalty to treasury or liquidator
  - Update totalSupply after burns
  - Emit LiquidationExecuted event with liquidator, msg.value, tokensToRemove, bounty
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8_
-

- [x] 14. Implement view functions for vault state queries (PARTIAL - missing getCurrentSupplyCap)
  - Implement getCurrentAura() external view function returning IAuraOracle(oracle).getAura(address(this)) ✓
  - Implement getPeg() public view function that fetches current aura and returns calculatePeg(aura) ✓
  - Implement getVaultState() external view function ✓
  - Return tuple: (creatorCollateral, fanCollateral, totalCollateral, totalSupply, getPeg(), stage, calculateHealth()) ✓
  - Implement getPosition(address owner, uint256 index) external view function ✓
  - Verify index < positions[owner].length ✓
  - Return positions[owner][index] ✓
  - Implement getPositionCount(address owner) external view function returning positions[owner].length ✓ (appears truncated in file)
  - Implement getCurrentSupplyCap() external view function that fetches current aura and returns calculateSupplyCap(aura) ❌ MISSING
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 14b. Complete view functions








  - Add getCurrentSupplyCap() external view function that fetches current aura and returns calculateSupplyCap(aura)
  - Verify getPositionCount() function is complete (file was truncated)
  - _Requirements: 8.3, 8.4, 8.5_

- [x] 14c. Add ICreatorToken interface to CreatorVault






  - Add ICreatorToken interface definition with mint(), burn(), and transferFrom() function signatures
  - Update all token interactions to use ICreatorToken interface casting
  - _Requirements: 1.4, 9.3_

- [x] 15. Add comprehensive events to all contracts (PARTIAL - missing SupplyCapShrink)
  - Add VaultCreated(address indexed creator, address vault, address token, uint256 baseCap) to VaultFactory ✓
  - Add StageConfigured(address indexed vault, uint8 stage, uint256 stakeRequired, uint256 mintCap) to VaultFactory ✓
  - Add StageUnlocked(address indexed vault, uint8 stage, uint256 stakeAmount) to CreatorVault ✓
  - Add Minted(address indexed vault, address indexed minter, uint256 qty, uint256 collateral, uint8 stage, uint256 peg) to CreatorVault ✓
  - Add Redeemed(address indexed vault, address indexed redeemer, uint256 qty, uint256 collateralReturned) to CreatorVault ✓
  - Note: AuraUpdated event is in AuraOracle contract, not CreatorVault ✓
  - Add SupplyCapShrink(address indexed vault, uint256 oldCap, uint256 newCap, uint256 pendingBurn, uint256 graceEndTs) to CreatorVault ❌ MISSING
  - Add ForcedBurnExecuted(address indexed vault, uint256 tokensBurned, uint256 collateralWrittenDown) to CreatorVault ✓
  - Add LiquidationExecuted(address indexed vault, address indexed liquidator, uint256 payCELO, uint256 tokensRemoved, uint256 bounty) to CreatorVault ✓
  - Add TreasuryCollected(address indexed vault, uint256 amount, string reason) to Treasury ✓
  - _Requirements: All requirements reference events_

- [x] 16. Implement custom errors for gas efficiency





  - Define custom errors in CreatorVault: InsufficientCollateral, StageNotUnlocked, ExceedsStageCap, ExceedsSupplyCap, HealthTooLow, NotLiquidatable, GracePeriodActive, Unauthorized, InsufficientPayment, InsufficientLiquidation
  - Note: CooldownNotElapsed error is in AuraOracle, not CreatorVault
  - Replace require statements with revert CustomError() for gas optimization
  - _Requirements: 9.1, 9.5_

- [x] 17. Add security modifiers and guards









  - Add nonReentrant modifier from OpenZeppelin ReentrancyGuard to mintTokens, redeemTokens, liquidate functions
  - Note: onlyOracle modifier is only in AuraOracle contract, not needed in CreatorVault
  - Add onlyOwner modifier to VaultFactory admin functions
  - Add Pausable functionality to CreatorVault for emergency stops
  - Implement whenNotPaused modifier on critical functions
  - _Requirements: 9.1, 9.2, 9.4, 9.5_

- [x] 18. Create deployment script for Celo Alfajores






  - Create script/Deploy.s.sol Foundry script
  - Deploy Treasury contract
  - Deploy AuraOracle contract with initial oracle address
  - Deploy VaultFactory contract with treasury and oracle addresses
  - Set default stage configurations for test vault
  - Log all deployed contract addresses
  - Save deployment addresses to deployments.json file
  - _Requirements: All requirements - deployment prerequisite_

- [x] 19. Implement oracle computation script





  - Create oracle/oracle.js Node.js script
  - Implement fetchFarcasterMetrics(creatorFid) function to get follower count, follower delta, avg likes, verification status
  - Implement computeAura(metrics) function with weighted normalization: aura = w1*norm(followers) + w2*norm(followerDelta) + w3*norm(avgLikes) + w4*verification - spamPenalty
  - Implement log-based normalization to map counts to 0-200 range
  - Add clamp function to ensure aura stays within A_MIN and A_MAX
  - Implement pinToIPFS(data) function using Pinata or Infura to store metrics JSON
  - Implement updateVaultAura(vaultAddress, aura, ipfsHash) function using ethers.js to call AuraOracle.pushAura (NOT CreatorVault.updateAura)
  - Note: Oracle script only updates AuraOracle contract; vaults read from it automatically
  - Add command-line interface to run oracle for specific creator vault
  - Include mock mode for testing with hardcoded metrics
  - _Requirements: 5.1, 5.6_

- [x] 20. Write comprehensive unit tests for Treasury












  - Test fee collection via collectFee()
  - Test owner withdrawal with correct amount
  - Test unauthorized withdrawal reverts
  - Test event emissions
  - _Requirements: 9.4_

- [x] 21. Write comprehensive unit tests for AuraOracle







  - Test pushAura with valid parameters
  - Test cooldown enforcement (revert if called too soon)
  - Test unauthorized caller reverts
  - Test getAura returns correct value
  - Test IPFS hash storage and retrieval
  - Test event emissions
  - _Requirements: 5.1, 5.2, 5.6, 9.2_

- [x] 22. Write comprehensive unit tests for CreatorToken







  - Test mint restricted to vault only
  - Test burn restricted to vault only
  - Test unauthorized mint/burn reverts
  - Test standard ERC20 functionality (transfer, approve, transferFrom)
  - _Requirements: 1.4, 9.3_


- [x] 23. Write comprehensive unit tests for VaultFactory






  - Test vault creation with valid parameters
  - Test vault and token deployment
  - Test VaultCreated event emission
  - Test setStageConfig by owner
  - Test unauthorized setStageConfig reverts
  - Test creator-to-vault registry mapping
  - _Requirements: 1.1, 1.2, 1.5, 9.4_

- [x] 24. Write comprehensive unit tests for creator stake functions







  - Test bootstrapCreatorStake with sufficient stake for stage 1
  - Test bootstrapCreatorStake with insufficient stake (stage remains 0)
  - Test unlockStage progression from stage 1 to 2, 2 to 3, etc.
  - Test unlockStage with insufficient additional stake reverts
  - Test StageUnlocked event emissions
  - Test collateral accounting (creatorCollateral, totalCollateral)
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 25. Write comprehensive unit tests for fan minting











  - Test successful mint with exact collateral requirement
  - Test mint with excess collateral (no refund in current design)
  - Test mint reverts when stage == 0
  - Test mint reverts when exceeding stage cap
  - Test mint reverts when exceeding supply cap
  - Test mint reverts with insufficient collateral
  - Test mint reverts when health would drop below MIN_CR
  - Test position creation and storage
  - Test fee transfer to treasury
  - Test token minting to fan
  - Test Minted event emission
  - Test multiple mints by same fan create multiple positions
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 26. Write comprehensive unit tests for token redemption







  - Test full position redemption
  - Test partial position redemption (FIFO)
  - Test redemption across multiple positions
  - Test redemption reverts when health would drop below MIN_CR
  - Test correct collateral calculation and return
  - Test token burning
  - Test Redeemed event emission
  - Test position state updates after redemption
  - Test redemption with zero balance reverts
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

- [x] 27. Write comprehensive unit tests for oracle aura reading and forced burn triggering







  - Test getCurrentAura() fetches correct value from AuraOracle
  - Test getPeg() calculates correct peg based on oracle aura
  - Test peg updates dynamically when oracle aura changes
  - Test supply cap updates dynamically when oracle aura changes
  - Test checkAndTriggerForcedBurn() with supply > cap (forced burn triggered)
  - Test checkAndTriggerForcedBurn() with supply <= cap (no action)
  - Test pendingForcedBurn and forcedBurnDeadline set correctly
  - Test SupplyCapShrink event emission
  - Test that mint/redeem use current oracle aura, not stale values
  - Test peg clamping at P_MIN and P_MAX boundaries
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.1, 8.4, 8.5_

- [ ]* 27b. Write integration tests for oracle-vault interaction
  - Test oracle updates AuraOracle, vault reads new value immediately
  - Test multiple vaults reading from same AuraOracle
  - Test vault operations (mint/redeem) use latest oracle aura
  - Test forced burn trigger after oracle aura drop
  - Test that vault never stores stale aura values
  - _Requirements: 5.1, 5.6, 8.4, 8.5_

- [ ]* 28. Write comprehensive unit tests for forced contraction
  - Test executeForcedBurn reverts before deadline
  - Test executeForcedBurn succeeds after deadline
  - Test pro-rata token burning across positions
  - Test proportional collateral write-down
  - Test batched processing with maxOwnersToProcess limit
  - Test multiple executeForcedBurn calls to complete large burn
  - Test pendingForcedBurn reduction after execution
  - Test totalSupply and totalCollateral updates
  - Test ForcedBurnExecuted event emission
  - Test forced burn with single position
  - Test forced burn with multiple positions across multiple owners
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

- [ ]* 29. Write comprehensive unit tests for liquidation
  - Test liquidation succeeds when health < LIQ_CR
  - Test liquidation reverts when health >= LIQ_CR
  - Test liquidation reverts with payCELO below minimum
  - Test correct calculation of tokens to remove
  - Test pro-rata token burning across positions
  - Test bounty payment to liquidator
  - Test remaining payCELO added to vault collateral
  - Test creator penalty extraction
  - Test health improvement after liquidation
  - Test LiquidationExecuted event emission
  - Test liquidation with insufficient payCELO (tokensToRemove <= 0) reverts
  - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8_

- [ ]* 30. Write comprehensive unit tests for view functions
  - Test getVaultState returns correct values
  - Test getPosition returns correct position data
  - Test getPosition with invalid index reverts
  - Test getPositionCount returns correct count
  - Test getCurrentSupplyCap returns correct value
  - Test health calculation accuracy
  - _Requirements: 8.1, 8.2, 8.3_

- [ ]* 31. Write comprehensive unit tests for mathematical functions
  - Test calculatePeg with various aura values (below A_REF, at A_REF, above A_REF)
  - Test calculatePeg clamping at P_MIN and P_MAX
  - Test calculateSupplyCap with various aura values
  - Test calculateSupplyCap clamping at bounds
  - Test calculateHealth with various collateral and supply values
  - Test calculateRequiredCollateral with various quantities and pegs
  - Test WAD math precision (no overflow, correct rounding)
  - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

- [ ]* 32. Write integration tests for full lifecycle scenarios
  - Test complete flow: create vault → bootstrap → mint → redeem
  - Test multi-stage progression: unlock stage 2, 3, 4 with increasing mints
  - Test aura rise scenario: mint at low peg, aura increases, redeem at high peg (value gain)
  - Test aura drop scenario: mint at high peg, aura drops, forced burn triggered, execute burn
  - Test liquidation scenario: create unhealthy vault, liquidator injects CELO, health restored
  - Test multiple fans with multiple positions: complex redemption and forced burn interactions
  - Test grace period behavior: fans redeem during grace window before forced burn
  - _Requirements: All requirements - integration validation_

- [ ]* 33. Write security and edge case tests
  - Test reentrancy attack attempts on mint, redeem, liquidate
  - Test access control: non-oracle updateAura, non-vault token mint/burn, non-owner factory admin
  - Test rounding edge cases: mint/redeem tiny amounts (1 wei)
  - Test boundary conditions: aura at A_MIN and A_MAX, peg at P_MIN and P_MAX
  - Test empty vault redemption (totalSupply == 0)
  - Test last redeemer gets remaining dust collateral
  - Test forced burn with single position fully burned
  - Test liquidation during grace period (both mechanisms active)
  - Test oracle stale data (no updates for extended period)
  - Test gas limits: 100 positions across 20 owners, batched forced burn
  - Test pausable functionality: pause vault, attempt operations, unpause
  - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

- [x] 34. Create README documentation (PARTIAL - needs updates to match actual implementation)
  - Write project overview and AuraFi concept explanation ✓
  - Document contract architecture and interactions ✓
  - Provide setup instructions: install Foundry, install dependencies ✓
  - Document deployment steps for Alfajores testnet ✓
  - Provide testing instructions: forge test, forge test -vvv for verbose ✓
  - Document oracle setup and usage ✓
  - Include example usage flows with CLI commands ✓
  - Add security considerations and audit status ❌ NEEDS UPDATE
  - Include links to deployed contracts on Alfajores ❌ NEEDS UPDATE
  - Document MVP limitations and future enhancements ❌ NEEDS UPDATE
  - Update README to reflect actual dual-collateral vault design (not ERC-4626) ❌ NEEDS UPDATE
  - _Requirements: All requirements - documentation_

- [ ] 34b. Update README to match implementation
  - Remove ERC-4626 references (vaults are not ERC-4626 compliant)
  - Update feature list to reflect dual-collateral model, staged progression, forced contraction, liquidation
  - Add architecture section explaining CreatorVault, VaultFactory, AuraOracle, Treasury, CreatorToken
  - Document key concepts: positions, stages, peg calculation, health ratio, forced burn, liquidation
  - Add usage examples for creator and fan flows
  - Document security considerations and known limitations
  - _Requirements: All requirements - documentation_

- [ ] 35. Create demo script for end-to-end demonstration
  - Create script/Demo.s.sol Foundry script
  - Deploy all contracts (factory, treasury, oracle)
  - Create test vault for demo creator
  - Bootstrap creator stake to unlock stage 1
  - Simulate fan mints at stage 1
  - Call oracle to update aura upward (peg increases)
  - Simulate more fan mints at higher peg
  - Call oracle to update aura downward (trigger forced burn)
  - Wait grace period and execute forced burn
  - Degrade health and perform liquidation
  - Log all state changes and events
  - Output summary of demo flow
  - _Requirements: All requirements - demonstration_

---

## Remaining Tasks to Complete MVP

### Critical (Required for Core Functionality)

- [ ] 11b. Complete forced burn implementation
  - Add SupplyCapShrink event to CreatorVault events section
  - Update checkAndTriggerForcedBurn() to emit SupplyCapShrink event when triggered
  - _Requirements: 6.1, 8.5_

- [ ] 12. Implement forced contraction execution with batched processing
  - Implement executeForcedBurn(uint256 maxOwnersToProcess) external function
  - Verify block.timestamp >= forcedBurnDeadline, revert with GracePeriodActive
  - Verify pendingForcedBurn > 0
  - Initialize totalBurned = 0 and totalWriteDown = 0
  - Iterate through positionOwners array up to maxOwnersToProcess limit
  - For each owner, iterate through their positions array
  - Calculate burnFromPosition = (position.qty * pendingForcedBurn) / totalSupply using WAD math (floor)
  - Calculate collateralWriteDown = (position.collateral * burnFromPosition) / position.qty
  - Reduce position.qty by burnFromPosition and position.collateral by collateralWriteDown
  - Call token.burn(owner, burnFromPosition)
  - Accumulate totalBurned and totalWriteDown
  - Update totalSupply and totalCollateral after processing
  - Reduce pendingForcedBurn by totalBurned
  - If pendingForcedBurn == 0, clear forcedBurnDeadline
  - Emit ForcedBurnExecuted event with totalBurned and totalWriteDown
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

- [ ] 14b. Complete view functions
  - Add getCurrentSupplyCap() external view function that fetches current aura and returns calculateSupplyCap(aura)
  - Verify getPositionCount() function is complete (file was truncated)
  - _Requirements: 8.3, 8.4, 8.5_

- [ ] 14c. Add ICreatorToken interface to CreatorVault
  - Add ICreatorToken interface definition with mint(), burn(), and transferFrom() function signatures
  - Update all token interactions to use ICreatorToken interface casting
  - _Requirements: 1.4, 9.3_

### Important (Recommended for Production)

- [ ] 34b. Update README to match implementation
  - Remove ERC-4626 references (vaults are not ERC-4626 compliant)
  - Update feature list to reflect dual-collateral model, staged progression, forced contraction, liquidation
  - Add architecture section explaining CreatorVault, VaultFactory, AuraOracle, Treasury, CreatorToken
  - Document key concepts: positions, stages, peg calculation, health ratio, forced burn, liquidation
  - Add usage examples for creator and fan flows
  - Document security considerations and known limitations
  - _Requirements: All requirements - documentation_

### Optional (Nice to Have)

- [ ] 35. Create demo script for end-to-end demonstration
  - Full implementation as described above
  - _Requirements: All requirements - demonstration_

### Optional Testing (Tasks 27-33)
All testing tasks marked with `*` are optional and provide comprehensive test coverage beyond the basic tests already implemented. These can be completed if thorough testing is desired before production deployment.
