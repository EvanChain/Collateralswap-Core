# UnlockX

A decentralized protocol for trading debt positions and collateral from Aave V3, built with Foundry. This protocol enables users to migrate their Aave positions into a tradeable format and create orders for swapping collateral and debt tokens.

## Features

- **Aave V3 Integration**: Seamlessly migrate positions from Aave V3 using flash loans
- **Position Trading**: Create tradeable orders for your collateral and debt positions
- **Router System**: Efficient order matching and execution across multiple PIV contracts
- **Flash Loan Support**: Gas-efficient position migration using Aave V3 flash loans
- **Flexible Order Management**: Place, update, and cancel orders with dynamic pricing

## Architecture

- **Router.sol**: Main entry point for deploying PIV contracts and executing swaps
- **PIV.sol**: Position-in-Vault contract that manages individual user positions and orders
- **IPIV.sol**: Interface defining the PIV contract functionality
- **IRouter.sol**: Interface for the router contract

## Smart Contracts

### Router Contract
- Deploys new PIV contracts for users
- Executes multi-order swaps across different PIV contracts
- Handles token transfers and minimum output validation

### PIV Contract
- Manages Aave V3 position migration via flash loans
- Handles order placement, updates, and cancellation
- Executes swaps between collateral and debt tokens
- Integrates with Aave V3 Pool for lending operations

## Getting Started

### Prerequisites
- [Foundry](https://getfoundry.sh/) installed
- Access to an Ethereum-compatible network with Aave V3 deployed

### Installation

```shell
# Clone the repository
git clone <repository-url>
cd lending-swap

# Install dependencies
forge soldeer update
forge build
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Deploy

```shell
# Deploy the Router contract
forge script script/DeployRouter.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Usage

### 1. Deploy a PIV Contract

```solidity
// Deploy through Router
address pivAddress = router.deployPIV();
```

### 2. Migrate from Aave V3

```solidity
// Migrate your Aave position to PIV
uint256 newDebtAmount = piv.migrateFromAave(
    collateralToken,
    collateralAmount,
    debtToken,
    debtAmount,
    interestRateMode
);
```

### 3. Place an Order

```solidity
// Create a tradeable order
uint256 orderId = piv.placeOrder(
    collateralToken,
    collateralAmount,
    debtToken,
    price,
    interestRateMode
);
```

### 4. Execute Swaps

```solidity
// Execute swap through Router
SwapData memory swapData = SwapData({
    tokenIn: debtToken,
    tokenOut: collateralToken,
    amountIn: inputAmount,
    minAmountOut: minOutput,
    orderDatas: orderDataArray
});

(uint256 amountOut, uint256 totalInput) = router.swap(swapData);
```

## Development Tools

### Format Code
```shell
forge fmt
```

### Gas Snapshots
```shell
forge snapshot
```

### Local Development
```shell
# Start local node
anvil

# Run tests with gas reporting
forge test --gas-report
```

### Verification
```shell
# Verify contracts on Etherscan
forge verify-contract <contract_address> <contract_name> --etherscan-api-key <api_key>
```

## Security Considerations

- Flash loan reentrancy protection
- Proper allowance management for ERC20 tokens
- Owner-only functions for order management
- Slippage protection with minimum output amounts

## License

MIT

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## Documentation

For more information about Foundry:
https://book.getfoundry.sh/
