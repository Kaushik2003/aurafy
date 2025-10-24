# Requirements Document

## Introduction

AuraFi is a creator-backed collateral protocol where creators and fans jointly underwrite a creator's on-chain token. Creators must stake real collateral and progress through aura-gated stages to unlock mint capacity; fans deposit collateral to mint tokens. A creator's Aura (derived from Farcaster activity) anchors token unit value (the peg) and unlocks new mint stages. If aura falls or vault health drops below thresholds, the protocol enacts forced contraction and liquidation that penalize both creators and fans—ensuring skin in the game and aligned incentives.

## Glossary

- **Vault**: A smart contract that holds creator and fan collateral and manages token minting/redemption for a specific creator
- **CreatorCollateral**: CELO tokens staked by the creator to unlock stages and back minted supply
- **FanCollateral**: CELO tokens deposited by fans when minting creator tokens
- **Aura**: A numeric score (0-200) derived from Farcaster activity that determines peg value and supply caps
- **Peg**: The CELO-per-token exchange rate, calculated as P(aura) and bounded between P_MIN and P_MAX
- **Stage**: Discrete progression levels (0..N) that gate minting capacity based on creator stake
- **Position**: A record of a fan's mint transaction including quantity, collateral, and stage
- **SupplyCap**: Maximum allowed token supply based on current aura, calculated as SupplyCap(aura)
- **Health**: Collateralization ratio calculated as TotalCollateral / (Supply * Peg)
- **MIN_CR**: Minimum collateralization ratio of 150% required for minting
- **LIQ_CR**: Liquidation threshold of 120% below which liquidation is triggered
- **ForcedContraction**: Protocol mechanism that burns tokens proportionally when supply exceeds SupplyCap after aura drop
- **Oracle**: Trusted address that updates aura values with IPFS evidence
- **VaultFactory**: Contract that deploys new vaults and tokens for creators
- **Treasury**: Contract that collects protocol fees

## Requirements

### Requirement 1: Vault Creation and Initialization

**User Story:** As a creator, I want to create a vault with my own token so that I can begin accepting fan collateral and minting tokens

#### Acceptance Criteria

1. WHEN a creator requests vault creation with name, symbol, and baseCap parameters, THE VaultFactory SHALL deploy a new CreatorVault contract and CreatorToken contract
2. WHEN a vault is created, THE VaultFactory SHALL emit a VaultCreated event containing creator address, vault address, token address, and baseCap
3. WHEN a vault is initialized, THE CreatorVault SHALL set stage to 0 and totalSupply to 0
4. WHEN a vault is created, THE CreatorToken SHALL restrict mint and burn operations to the vault address only
5. WHEN stage configuration is set, THE VaultFactory SHALL store stakeRequired and mintCap for each stage from 0 to N

### Requirement 2: Creator Stake and Stage Progression

**User Story:** As a creator, I want to deposit collateral to unlock higher stages so that I can increase my token's mint capacity

#### Acceptance Criteria

1. WHEN a creator deposits CELO via bootstrapCreatorStake, THE CreatorVault SHALL record the amount as creatorCollateral and increment totalCollateral
2. WHEN creator collateral meets or exceeds the stakeRequired for stage 1, THE CreatorVault SHALL set stage to 1 and emit StageUnlocked event
3. WHEN a creator calls unlockStage with sufficient CELO for the next stage, THE CreatorVault SHALL increment stage by 1 and update creatorCollateral
4. WHEN a creator attempts to unlock a stage without sufficient stake, THE CreatorVault SHALL revert the transaction
5. WHEN a stage is unlocked, THE CreatorVault SHALL make the corresponding stageMintCap available for fan minting

### Requirement 3: Fan Token Minting with Position Tracking

**User Story:** As a fan, I want to mint creator tokens by depositing CELO collateral so that I can support the creator and hold their tokens

#### Acceptance Criteria

1. WHEN a fan calls mintTokens with quantity q and sufficient CELO, THE CreatorVault SHALL calculate requiredCollateral as q * peg * MIN_CR plus MINT_FEE
2. WHEN minting is requested, THE CreatorVault SHALL verify that stage is greater than 0 and totalSupply plus q does not exceed stageMintCap for current stage
3. WHEN minting is requested, THE CreatorVault SHALL verify that totalSupply plus q does not exceed SupplyCap based on lastAura
4. WHEN collateral requirements are met, THE CreatorVault SHALL create a Position record with owner, qty, collateral (minus fee), stage, and createdAt timestamp
5. WHEN a position is created, THE CreatorVault SHALL mint q tokens to the fan via CreatorToken, update fanCollateral and totalCollateral, and emit Minted event
6. WHEN minting would cause Health to fall below MIN_CR, THE CreatorVault SHALL revert the transaction
7. WHEN a mint fee is collected, THE CreatorVault SHALL transfer the fee amount to the Treasury contract

### Requirement 4: Token Redemption with Position-Based Accounting

**User Story:** As a fan, I want to redeem my tokens for CELO collateral so that I can exit my position and recover my investment

#### Acceptance Criteria

1. WHEN a fan calls redeemTokens with quantity q, THE CreatorVault SHALL verify the fan holds at least q tokens
2. WHEN redemption is processed, THE CreatorVault SHALL iterate through the fan's positions in FIFO order and calculate collateralToReturn proportionally
3. WHEN calculating redemption, THE CreatorVault SHALL compute HealthAfter as (totalCollateral minus collateralToReturn) divided by ((totalSupply minus q) times peg)
4. WHEN HealthAfter is greater than or equal to MIN_CR, THE CreatorVault SHALL transfer collateralToReturn CELO to the fan and burn q tokens
5. WHEN HealthAfter would be less than MIN_CR, THE CreatorVault SHALL revert the transaction
6. WHEN redemption completes, THE CreatorVault SHALL update position quantities, fanCollateral, totalCollateral, totalSupply, and emit Redeemed event

### Requirement 5: Oracle Aura Updates with Evidence

**User Story:** As an oracle operator, I want to update a creator's aura with IPFS evidence so that the protocol can adjust peg and supply caps based on creator activity

#### Acceptance Criteria

1. WHEN updateAura is called with aura and ipfsHash, THE CreatorVault SHALL verify the caller is the registered oracle address
2. WHEN an aura update is requested, THE CreatorVault SHALL verify that ORACLE_UPDATE_COOLDOWN has elapsed since the last update
3. WHEN aura is updated, THE CreatorVault SHALL calculate newPeg using the formula P(aura) = BASE_PRICE * (1 + K * (aura/A_REF - 1)) clamped between P_MIN and P_MAX
4. WHEN aura is updated, THE CreatorVault SHALL calculate newSupplyCap using SupplyCap(aura) = BaseCap * (1 + s * (aura - A_REF) / A_REF) clamped appropriately
5. WHEN totalSupply exceeds newSupplyCap, THE CreatorVault SHALL set pendingForcedBurn to (totalSupply minus newSupplyCap), set forcedBurnDeadline to (block.timestamp plus FORCED_BURN_GRACE), and emit SupplyCapShrink event
6. WHEN aura update completes without supply cap violation, THE CreatorVault SHALL update lastAura, peg, and emit AuraUpdated event with ipfsHash

### Requirement 6: Forced Contraction After Grace Period

**User Story:** As a protocol participant, I want the system to automatically reduce token supply when aura drops so that the peg remains backed by sufficient collateral

#### Acceptance Criteria

1. WHEN executeForcedBurn is called after forcedBurnDeadline, THE CreatorVault SHALL calculate requiredBurn from pendingForcedBurn
2. WHEN processing forced burn, THE CreatorVault SHALL iterate through positionOwners up to maxOwnersToProcess limit for gas safety
3. WHEN burning from a position, THE CreatorVault SHALL calculate burnFromPosition as floor(position.qty * requiredBurn / totalSupply)
4. WHEN burning from a position, THE CreatorVault SHALL calculate collateralWriteDown as position.collateral * (burnFromPosition / position.qty)
5. WHEN forced burn is executed, THE CreatorVault SHALL reduce position.qty, position.collateral, totalSupply, and totalCollateral by calculated amounts
6. WHEN forced burn is executed, THE CreatorVault SHALL call CreatorToken.burn for each affected position
7. WHEN forced burn processing completes, THE CreatorVault SHALL reduce pendingForcedBurn and emit ForcedBurnExecuted event with totalBurned and totalWriteDown
8. WHEN executeForcedBurn is called before forcedBurnDeadline, THE CreatorVault SHALL revert the transaction

### Requirement 7: Liquidation Mechanism for Undercollateralized Vaults

**User Story:** As a liquidator, I want to inject CELO to buy down supply in unhealthy vaults so that I can earn a bounty and restore vault health

#### Acceptance Criteria

1. WHEN liquidate is called with payCELO, THE CreatorVault SHALL verify that Health is less than LIQ_CR
2. WHEN liquidation is triggered, THE CreatorVault SHALL calculate tokens to burn as x = Supply minus floor((Collateral plus payCELO) / (peg * MIN_CR))
3. WHEN x is less than or equal to 0, THE CreatorVault SHALL revert the transaction
4. WHEN liquidation proceeds, THE CreatorVault SHALL burn x tokens proportionally across positions using batch logic
5. WHEN tokens are burned, THE CreatorVault SHALL transfer bounty equal to payCELO * LIQUIDATION_BOUNTY to the liquidator
6. WHEN bounty is paid, THE CreatorVault SHALL add remainder (payCELO minus bounty) to totalCollateral
7. WHEN liquidation completes, THE CreatorVault SHALL extract creatorPenalty from creatorCollateral and emit LiquidationExecuted event
8. WHEN payCELO is below minimum threshold, THE CreatorVault SHALL revert the transaction to prevent griefing

### Requirement 8: View Functions for Vault State

**User Story:** As a user or UI developer, I want to query vault state and position data so that I can display accurate information and make informed decisions

#### Acceptance Criteria

1. WHEN getVaultState is called, THE CreatorVault SHALL return creatorCollateral, fanCollateral, totalCollateral, totalSupply, peg, stage, and health
2. WHEN getPosition is called with owner and index, THE CreatorVault SHALL return the Position struct containing owner, qty, collateral, stage, and createdAt
3. WHEN health is calculated, THE CreatorVault SHALL use the formula Health = totalCollateral / (totalSupply * peg)
4. WHEN getAura is called on AuraOracle, THE AuraOracle SHALL return the last recorded aura for the specified vault

### Requirement 9: Security and Access Control

**User Story:** As a protocol administrator, I want strict access controls and security measures so that the system is protected from unauthorized actions and attacks

#### Acceptance Criteria

1. WHEN any state-mutating function is called, THE CreatorVault SHALL apply nonReentrant modifier to prevent reentrancy attacks
2. WHEN updateAura is called, THE CreatorVault SHALL verify the caller address matches the registered oracle address
3. WHEN CreatorToken mint or burn is called, THE CreatorToken SHALL verify the caller is the vault contract
4. WHEN VaultFactory administrative functions are called, THE VaultFactory SHALL verify the caller is the contract owner
5. WHEN emergency conditions occur, THE CreatorVault SHALL support pausable functionality controlled by owner multisig

### Requirement 10: Mathematical Precision and Fixed-Point Arithmetic

**User Story:** As a protocol developer, I want all calculations to use fixed-point arithmetic so that precision is maintained and rounding errors are minimized

#### Acceptance Criteria

1. WHEN percentage values are stored, THE contracts SHALL use WAD (1e18) fixed-point representation
2. WHEN peg is calculated, THE CreatorVault SHALL use WAD arithmetic with proper scaling for aura normalization
3. WHEN collateral requirements are calculated, THE CreatorVault SHALL use WAD multiplication and division with appropriate rounding
4. WHEN supply cap is calculated, THE CreatorVault SHALL apply WAD arithmetic and clamp results to defined bounds
5. WHEN health is calculated, THE CreatorVault SHALL use WAD division to maintain precision in the ratio
