# Delaunch Contracts

Smart contracts for deploying tokens on a bonding curve & Pharaoh CL pool.

# Bonding curve

This contract aims to deploy 80% of tokens created into the bonding curve with a 250 avax required to fill the curve (252.5 avax) if accounting for 1% fees

After curve reaches 250 avax filled, the expected behavior is that 20% of the tokens are then deposited + 250 avax raised into the CL Pool.

## Overview

The system consists of the following main components:

1. `DelaunchTokenV2.sol` - Basic ERC20 token implementation
2. `DelaunchFactoryV2.sol` - Main contract for deploying tokens on the bonding curve & creating Pharaoh CL pool liquidity
3. Interfaces and Libraries:
   - `IUniswapV3.sol` - Uniswap V3 interfaces
   - `Bytes32AddressLib.sol` - Address manipulation utilities

## Setup

1. Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:

```bash
forge install https://github.com/OpenZeppelin/openzeppelin-contracts
forge install https://github.com/foundry-rs/forge-std
forge install https://github.com/abdk-consulting/abdk-libraries-solidity.git
```

3. Create a `.env` file:

```bash
cp .env.example .env
# Fill in your environment variables
```

## Development

1. Build:

```bash
forge build
```

2. Test:

```bash
forge test -vv
```

## Contract Architecture

### DelaunchTokenV2

- Basic ERC20 implementation
- Fixed supply minted to deployer
- 18 decimals
- Not transferrable until curveComplete() is completed (called by DelaunchFactoryV2 when token graduates)

### DelaunchFactoryV2

- Deploys new tokens with CREATE2 for address prediction
- Facilitate bonding curves for all tokens of the page
- Creates Uniswap V3 pool with initial liquidity
- Locks liquidity in time-lock contract
- Handles protocol fees and token swaps

## Integration

The contracts integrate with:

- Uniswap V3 for liquidity provision
- OpenZeppelin for standard implementations
- Custom liquidity locker for LP token locking

## Security

Key security features:

- CREATE2 for deterministic addresses
- Ownable for admin functions
- Input validation for all parameters
- Protocol fee handling
- Liquidity locking

## Testing

Tests cover:

- Token deployment
- Handling Pharaoh CL pool deployment when bonding curve is filled
- Address prediction
- Salt generation
- Admin functions
- Fee handling
- Error cases

## Environment Variables

Required environment variables:

```
DEPLOYER_PRIVATE_KEY=
AVALANCHE_RPC=
FEE_RECEIVER_ADDRESS=
DEPLOYER_ADDRESS=
CREATOR_ADDRESS=
```
