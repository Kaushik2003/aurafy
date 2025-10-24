Here is the corrected version of your README file. I've removed the garbled text at the very end.

-----

# AuraFi - Creator Vaults

AuraFi is a decentralized protocol for creator-backed vaults on Celo. Fans can invest in creator vaults, with returns tied to the creator's social reputation (aura score) derived from Farcaster metrics.

## Project Structure

```
├── contracts/          # Solidity smart contracts
│   ├── CreatorVault.sol    # Individual creator vault
│   └── VaultFactory.sol    # Factory for deploying vaults
├── script/             # Deployment scripts
├── test/               # Contract tests
└── oracle/             # Off-chain oracle for aura computation
    ├── oracle.js           # Main oracle script
    ├── test-oracle.js      # Oracle tests
    └── README.md           # Oracle documentation
```

## Quick Start

### 1\. Install Dependencies

**Smart Contracts:**

```shell
forge install
```

**Oracle:**

```shell
cd oracle
npm install
```

### 2\. Build Contracts

```shell
forge build
```

### 3\. Run Tests

**Contract Tests:**

```shell
forge test
```

**Oracle Tests:**

```shell
cd oracle
npm test
```

### 4\. Configure Oracle

Copy the example environment file:

```shell
cd oracle
cp .env.example .env.local
```

Edit `.env.local` with your API keys:

  - `NEYNAR_API_KEY` - For Farcaster data (free tier works)
  - `PINATA_API_KEY` / `PINATA_SECRET_KEY` - For IPFS pinning
  - `ORACLE_PRIVATE_KEY` - Oracle wallet private key
  - `RPC_URL` - Network RPC endpoint

### 5\. Deploy Contracts

```shell
forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```

### 6\. Run Oracle

Test with mock data:

```shell
cd oracle
node oracle.js --vault <vault_address> --fid <farcaster_id> --mock --dry-run
```

Run with live data:

```shell
node oracle.js --vault <vault_address> --fid <farcaster_id>
```

## Features

  - **Creator Vaults**: ERC-4626 compliant vaults for each creator
  - **Dynamic Aura**: Social reputation score (0-200) from Farcaster metrics
  - **Yield Adjustment**: Returns scale with creator's aura performance
  - **Oracle System**: Off-chain computation with on-chain verification
  - **IPFS Audit Trail**: All aura updates include verifiable evidence
  - **Free Tier Compatible**: Works with Neynar's free API tier

## Documentation

  - [Oracle Documentation](https://www.google.com/search?q=oracle/README.md) - Detailed oracle setup and usage
  - [Foundry Book](https://book.getfoundry.sh/) - Smart contract development

## Foundry Commands

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

### Local Node

```shell
anvil
```

### Cast

```shell
cast <subcommand>
```

### Help

```shell
forge --help
anvil --help
cast --help
```

## License

MIT