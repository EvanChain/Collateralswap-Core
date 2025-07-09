// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAaveV3PoolMinimal} from "./extensions/IAaveV3PoolMinimal.sol";
import {IAaveV3FlashLoanReceiver} from "./extensions/IAaveV3FlashLoanReceiver.sol";
import {IPIV} from "./IPIV.sol";

contract PIV is IAaveV3FlashLoanReceiver, Ownable {
    using SafeERC20 for IERC20;

    address public immutable POOL;
    address public immutable ADDRESSES_PROVIDER;

    uint256 totalOrders;
    mapping(uint256 => IPIV.Order) public orderMapping;

    constructor(address aavePool, address aaveAddressProvider) Ownable(msg.sender) {
        POOL = aavePool;
        ADDRESSES_PROVIDER = aaveAddressProvider;
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address, bytes calldata params)
        external
        override
        returns (bool)
    {
        require(msg.sender == POOL, "Invalid caller");
        (address user, IERC20 collateralAtoken, uint256 aTokenAmount, uint256 interestMode) =
            abi.decode(params, (address, IERC20, uint256, uint256));
        //repay old debt
        IERC20(asset).safeIncreaseAllowance(POOL, amount);
        uint256 finalRepayment = IAaveV3PoolMinimal(POOL).repay(asset, amount + premium, interestMode, user);
        //transfer aToken from user to this contract
        collateralAtoken.safeTransferFrom(user, address(this), aTokenAmount);
        //borrow new debt
        uint256 newDebtAmount = premium + finalRepayment;
        assembly {
            tstore(0, newDebtAmount)
        }
        IAaveV3PoolMinimal(POOL).borrow(asset, newDebtAmount, interestMode, 0, address(this));
        IERC20(asset).safeIncreaseAllowance(POOL, amount + premium);
        return true;
    }

    function atokenAddress(address asset) public view returns (address) {
        return IAaveV3PoolMinimal(POOL).getReserveData(asset).aTokenAddress;
    }

    // interestMode 1 for Stable, 2 for Variable
    function migrateFromAave(
        IERC20 collateralToken,
        uint256 collateralAmount,
        IERC20 debtToken,
        uint256 debtAmount,
        uint256 interestRateMode
    ) external onlyOwner returns (uint256 newDebtAmount) {
        bytes memory params = abi.encode(msg.sender, collateralToken, collateralAmount, interestRateMode);
        IAaveV3PoolMinimal(POOL).flashLoanSimple(address(this), address(debtToken), debtAmount, params, 0);
        assembly {
            newDebtAmount := tload(0)
        }
        // check ltv
        _checkHealthFactor();
        emit IPIV.LoanMigrated(
            msg.sender, address(collateralToken), address(debtToken), collateralAmount, newDebtAmount, interestRateMode
        );
    }

    function _checkHealthFactor() internal view {
        (,,,,, uint256 healthFactor) = IAaveV3PoolMinimal(POOL).getUserAccountData(address(this));
        require(healthFactor > 1 ether, "Health factor too low");
    }

    function placeOrder(
        address collateralToken,
        uint256 collateralAmount,
        address debtToken,
        uint256 price,
        uint256 interestRateMode
    ) external onlyOwner returns (uint256 orderId) {
        require(collateralAmount > 0 && price > 0, "Invalid collateral or price");
        address aToken = atokenAddress(collateralToken);
        require(IERC20(aToken).balanceOf(address(this)) >= collateralAmount, "Insufficient collateral balance");
        orderId = totalOrders++;
        orderMapping[orderId] = IPIV.Order({
            collateralToken: collateralToken,
            debtToken: debtToken,
            collateralAmount: collateralAmount,
            remainingCollateral: collateralAmount,
            price: price,
            interestRateMode: interestRateMode
        });

        emit IPIV.OrderPlaced(
            msg.sender, orderId, collateralToken, debtToken, collateralAmount, price, interestRateMode
        );
    }

    function updateOrder(uint256 orderId, uint256 price) external onlyOwner {
        IPIV.Order memory order = orderMapping[orderId];
        require(order.price != 0, "Order does not exist");
        require(price > 0, "Invalid price");
        orderMapping[orderId].price = price;

        emit IPIV.OrderUpdated(orderId, price);
    }

    function cancelOrder(uint256 orderId) external onlyOwner {
        delete orderMapping[orderId];
        emit IPIV.OrderCancelled(orderId);
    }

    function previewSwap(uint256[] calldata orderIds, uint256 tradingAmount)
        external
        view
        returns (uint256 debtInput, uint256 collateralOutput)
    {
        for (uint256 i = 0; i < orderIds.length; i++) {
            IPIV.Order storage order = orderMapping[orderIds[i]];
            debtInput += (tradingAmount * order.price + 1e18 - 1) / 1e18; // Assuming price is in 18 decimals
            if (tradingAmount > order.remainingCollateral) {
                collateralOutput += order.remainingCollateral; // Adjust to remaining collateral if more is requested
                tradingAmount -= order.remainingCollateral; // Reduce the trading amount by the remaining collateral
            } else {
                collateralOutput += tradingAmount;
            }
        }
    }

    function swap(uint256[] calldata orderIds, uint256 tradingAmount, address recipient)
        external
        returns (uint256 totalCollateralOutput, uint256 totalDebtInput)
    {
        uint256 remainningAmount = tradingAmount;
        for (uint256 i = 0; i < orderIds.length; i++) {
            (uint256 collateralOutput, uint256 debtInput) = _swap(orderIds[i], remainningAmount, recipient);
            totalCollateralOutput += collateralOutput;
            totalDebtInput += debtInput;
            remainningAmount -= collateralOutput;
            if (remainningAmount == 0) break;
        }
        _checkHealthFactor();
    }

    function _swap(uint256 orderId, uint256 tradingAmount, address recipient) internal returns (uint256, uint256) {
        IPIV.Order storage order = orderMapping[orderId];
        require(order.remainingCollateral >= tradingAmount, "Insufficient collateral");
        if (tradingAmount > order.remainingCollateral) {
            tradingAmount = order.remainingCollateral; // Adjust to remaining collateral if more is requested
            order.remainingCollateral = 0; // All collateral used
        } else {
            order.remainingCollateral -= tradingAmount;
        }
        order.remainingCollateral -= tradingAmount;

        uint256 debtAmount = (tradingAmount * order.price + 1e18 - 1) / 1e18; // Assuming price is in 18 decimals
        IERC20(order.debtToken).safeTransferFrom(msg.sender, address(this), debtAmount);
        IERC20(order.debtToken).safeIncreaseAllowance(POOL, debtAmount);
        // Repay the debt
        // Note: This assumes the debt token is the same as the one used in the order
        IAaveV3PoolMinimal(POOL).repay(order.debtToken, debtAmount, order.interestRateMode, address(this));
        // Transfer the trading amount to the caller
        address aToken = atokenAddress(order.collateralToken);
        IERC20(aToken).safeIncreaseAllowance(POOL, tradingAmount);
        IAaveV3PoolMinimal(POOL).withdraw(order.collateralToken, tradingAmount, recipient);
        emit IPIV.OrderTraded(orderId, tradingAmount);
        // Logic to handle the swap can be added here
        return (tradingAmount, debtAmount);
    }
}
