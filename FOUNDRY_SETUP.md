# Foundry Setup for ASLE Contracts

## Migration from Hardhat to Foundry

The ASLE project has been migrated from Hardhat to Foundry for smart contract development.

## Installation

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
```

2. Verify installation:
```bash
forge --version
cast --version
anvil --version
```

## Project Structure

```
contracts/
├── src/              # Source contracts
│   ├── core/        # Diamond and facets
│   ├── interfaces/  # Contract interfaces
│   └── libraries/   # Utility libraries
├── test/            # Test files (*.t.sol)
├── script/          # Deployment scripts (*.s.sol)
├── lib/             # Dependencies (git submodules)
└── foundry.toml     # Foundry configuration
```

## Commands

### Build
```bash
forge build
```

### Test
```bash
forge test              # Run all tests
forge test -vvv         # Verbose output
forge test --gas-report # With gas reporting
forge coverage          # Coverage report
```

### Deploy
```bash
# Local deployment (Anvil)
anvil
forge script script/Deploy.s.sol --broadcast

# Testnet/Mainnet
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast --verify
```

### Format & Lint
```bash
forge fmt              # Format code
forge fmt --check      # Check formatting
```

## Dependencies

Dependencies are managed via git submodules in `lib/`:

- `forge-std` - Foundry standard library
- `openzeppelin-contracts` - OpenZeppelin contracts

Install new dependencies:
```bash
forge install <github-user>/<repo>
```

## Remappings

Remappings are configured in `foundry.toml`:
- `@openzeppelin/` → `lib/openzeppelin-contracts/`
- `forge-std/` → `lib/forge-std/src/`

## Differences from Hardhat

1. **Test Files**: Use `.t.sol` extension (Solidity) instead of `.ts` (TypeScript)
2. **Scripts**: Use `.s.sol` extension (Solidity) instead of JavaScript
3. **Dependencies**: Git submodules instead of npm packages
4. **Configuration**: `foundry.toml` instead of `hardhat.config.ts`
5. **Build Output**: `out/` directory instead of `artifacts/`

## Local Development

Start local node:
```bash
anvil
```

Deploy to local node:
```bash
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Environment Variables

Set in `.env` file:
```
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_etherscan_key
RPC_URL=your_rpc_url
```

