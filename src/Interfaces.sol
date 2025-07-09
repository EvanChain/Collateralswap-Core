// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPIV {
    event LoanMigrated(
        address indexed user,
        address indexed collateralToken,
        address indexed debtToken,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 interestRateMode
    );

    /// @notice Migrate from Aave to PIV
    /// @dev This function allows users to migrate their collateral and debt from Aave to PIV.
    /// @param collateralAtoken The address of the aToken representing the collateral asset
    /// @param atokenAmount The amount of aTokens to migrate as collateral
    /// @param debtToken The address of the debt token to migrate
    /// @param debtAmount The amount of debt to migrate
    /// @param interestRateMode The interest rate mode of the debt (1 for stable, 2 for variable)
    /// @return newDebtAmount The new amount of debt after migration
    function migrateFromAave(
        address collateralAtoken,
        uint256 atokenAmount,
        address debtToken,
        uint256 debtAmount,
        uint256 interestRateMode
    ) external returns (uint256 newDebtAmount);
}

interface IOrderBook {
    /// @notice Emitted when an order is placed
    /// @param owner The address of the user who placed the order
    /// @param orderId The ID of the order
    /// @param collateralToken The address of the collateral token
    /// @param debtToken The address of the debt token
    /// @param collateralAmount The amount of collateral provided in the order
    /// @param price The price at which the order is placed (collateral/debt decimal is 18)
    event OrderPlaced(
        address indexed owner,
        uint256 indexed orderId,
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 price
    );

    /// @notice Emitted when an order is updated
    /// @param orderId The ID of the order that was updated
    /// @param collateralAmount The new amount of collateral provided in the order
    /// @param price The new price at which the order is placed (collateral/debt
    event OrderUpdated(
        uint256 indexed orderId, uint256 collateralAmount, uint256 price
    );
    /// @notice Emitted when an order is cancelled
    /// @param orderId The ID of the order that was cancelled
    event OrderCancelled(uint256 indexed orderId);

    /// @notice Emitted when an order is traded
    /// @param orderId The ID of the order that was traded
    /// @param tradingAmount The amount of collateral that was traded in the order
    event OrderTraded(uint256 indexed orderId, uint256 tradingAmount);

    /// @notice Emitted when a swap is executed
    /// @param tokenIn The address of the token being sold (debt token)
    /// @param tokenOut The address of the token being bought (collateral Token)
    /// @param amountIn The amount of the token being sold (debt token)
    /// @param finalAmountOut The final amount of the token being bought (collateral Token)
    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 finalAmountOut);

    /// @notice Place an order in the PIV system
    /// @dev This function allows users to place an order with collateral and debt.
    /// @param collateralAtoken The address of the aToken representing the collateral asset
    /// @param atokenAmount The amount of aTokens to sell
    /// @param debtToken The address of the debt token you want to buy
    /// @param price The price bewtween the collateral and debt token(collateral/debt decimal is 18)
    /// @return orderId The ID of the created order
    function placeOrder(address collateralAtoken, uint256 atokenAmount, address debtToken, uint256 price)
        external
        returns (uint256 orderId);

    /// @notice Update an existing order in the PIV system
    /// @param orderId the ID of the order to update
    /// @param atokenAmount The new amount of aTokens to sell
    /// @param price The new price between the collateral and debt token (collateral/debt decimal is 18)
    /// @dev This function allows users to update the amount and price of an existing order.
    function updateOrder(uint256 orderId, uint256 atokenAmount, uint256 price) external;

    /// @notice Cancel an existing order in the PIV system
    /// @param orderId The ID of the order to cancel
    function cancelOrder(uint256 orderId) external;

    /// @notice Trade an order in the PIV system
    /// @param tokenIn The address of the token being sold (debt token)
    /// @param tokenOut The address of the token being bought (collateral aToken)
    /// @param amountIn The amount of the token being sold (debt token)
    /// @param minAmountOut The minimum amount of the token being bought (collateral aToken)
    /// @param orderIds The IDs of the orders to be traded
    /// @return netAmountOut The net amount of the token being bought (collateral aToken)
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256[] calldata orderIds
    ) external returns (uint256 netAmountOut);
}
