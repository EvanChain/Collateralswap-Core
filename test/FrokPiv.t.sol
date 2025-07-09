// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test} from "forge-std/Test.sol";
import {PIV, IPIV} from "../src/PIV.sol";
import {Router, IRouter} from "../src/Router.sol";
import {IAaveV3PoolMinimal} from "../src/extensions/IAaveV3PoolMinimal.sol";

contract FrokPiv is Test {
    address constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; // Aave V3 Pool on Ethereum Mainnet
    address constant AAVE_V3_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    IAaveV3PoolMinimal aavePool = IAaveV3PoolMinimal(AAVE_V3_POOL);

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address aWeth;

    PIV piv;
    Router router;

    address borrower = vm.addr(1);
    address trader = vm.addr(2);
    uint256 interestRate = 2; // Float interest rate mode
    uint256 debtAmount = 1000e6;
    uint256 collateralAmount = 1 ether;

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL);
        vm.prank(borrower);
        //create the vault
        piv = new PIV(AAVE_V3_POOL, AAVE_V3_ADDRESS_PROVIDER);
        // Create the router
        router = new Router();
        aWeth = piv.atokenAddress(weth);

        // Ensure the user has Collateral tokens
        deal(weth, borrower, collateralAmount);

        // Initialize the loan in aave
        vm.startPrank(borrower);
        IERC20(weth).approve(address(aavePool), collateralAmount); // Approve WETH for supply
        aavePool.supply(weth, collateralAmount, borrower, 0); // Supply collateralAmount WETH as collateral
        aavePool.borrow(usdc, debtAmount, interestRate, 0, borrower); // Borrow 1000 USDC

        assertEq(IERC20(usdc).balanceOf(borrower), debtAmount, "User should have 1000 USDC");
        assertEq(IERC20(aWeth).balanceOf(borrower), collateralAmount, "User should have 1 aWETH");

        // migrate the vault to PI
        IERC20(aWeth).approve(address(piv), collateralAmount);
        piv.migrateFromAave(IERC20(aWeth), collateralAmount, IERC20(usdc), debtAmount, interestRate);
        assertEq(IERC20(aWeth).balanceOf(borrower), 0, "User should have 0 aWETH after migration");
        assertEq(
            IERC20(aWeth).balanceOf(address(piv)),
            collateralAmount,
            "PIV should have collateralAmount aWETH after migration"
        );

        vm.stopPrank();
    }

    function testPlaceOrder() public {
        vm.startPrank(borrower);

        // Define order parameters
        uint256 orderCollateralAmount = 0.5 ether; // Half of the available collateral
        uint256 orderPrice = 2000e18; // Price: 1 WETH = 2000 USDC (in 18 decimals)

        // Check initial state
        uint256 initialTotalOrders = piv.totalOrders();
        uint256 expectedOrderId = initialTotalOrders;

        // Check that PIV has sufficient collateral balance
        uint256 pivCollateralBalance = IERC20(aWeth).balanceOf(address(piv));
        assertGe(pivCollateralBalance, orderCollateralAmount, "PIV should have sufficient collateral");

        // Expect the OrderPlaced event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderPlaced(
            borrower,
            expectedOrderId,
            weth, // collateralToken
            usdc, // debtToken
            orderCollateralAmount,
            orderPrice,
            interestRate
        );

        // Place the order
        uint256 orderId = piv.placeOrder(
            weth, // collateralToken
            orderCollateralAmount,
            usdc, // debtToken
            orderPrice,
            interestRate
        );

        // Verify the returned order ID
        assertEq(orderId, expectedOrderId, "Order ID should match expected value");

        // Verify total orders increased
        assertEq(piv.totalOrders(), initialTotalOrders + 1, "Total orders should increase by 1");

        // Verify the order was stored correctly
        (
            address storedCollateralToken,
            address storedDebtToken,
            uint256 storedCollateralAmount,
            uint256 storedRemainingCollateral,
            uint256 storedPrice,
            uint256 storedInterestRateMode
        ) = piv.orderMapping(orderId);

        assertEq(storedCollateralToken, weth, "Stored collateral token should match");
        assertEq(storedDebtToken, usdc, "Stored debt token should match");
        assertEq(storedCollateralAmount, orderCollateralAmount, "Stored collateral amount should match");
        assertEq(storedRemainingCollateral, orderCollateralAmount, "Remaining collateral should equal initial amount");
        assertEq(storedPrice, orderPrice, "Stored price should match");
        assertEq(storedInterestRateMode, interestRate, "Stored interest rate mode should match");

        vm.stopPrank();
    }

    function testPlaceOrderRevertInvalidCollateral() public {
        vm.startPrank(borrower);

        // Test with zero collateral amount
        vm.expectRevert("Invalid collateral or price");
        piv.placeOrder(
            weth,
            0, // Invalid: zero collateral
            usdc,
            2000e18,
            interestRate
        );

        vm.stopPrank();
    }

    function testPlaceOrderRevertInvalidPrice() public {
        vm.startPrank(borrower);

        // Test with zero price
        vm.expectRevert("Invalid collateral or price");
        piv.placeOrder(
            weth,
            0.5 ether,
            usdc,
            0, // Invalid: zero price
            interestRate
        );

        vm.stopPrank();
    }

    function testPlaceOrderRevertInsufficientBalance() public {
        vm.startPrank(borrower);

        uint256 pivBalance = IERC20(aWeth).balanceOf(address(piv));
        uint256 excessiveAmount = pivBalance + 1 ether;

        // Test with amount exceeding available balance
        vm.expectRevert("Insufficient collateral balance");
        piv.placeOrder(weth, excessiveAmount, usdc, 2000e18, interestRate);

        vm.stopPrank();
    }

    function testPlaceOrderOnlyOwner() public {
        // Test that only owner can place orders
        vm.startPrank(trader); // Different address, not the owner

        vm.expectRevert(); // Should revert with Ownable: caller is not the owner
        piv.placeOrder(weth, 0.5 ether, usdc, 2000e18, interestRate);

        vm.stopPrank();
    }

    function testUpdateOrder() public {
        vm.startPrank(borrower);

        // First, place an order to update
        uint256 orderCollateralAmount = 0.5 ether;
        uint256 originalPrice = 2000e18;
        uint256 orderId = piv.placeOrder(weth, orderCollateralAmount, usdc, originalPrice, interestRate);

        // Define new price for update
        uint256 newPrice = 2500e18; // Updated price: 1 WETH = 2500 USDC

        // Expect the OrderUpdated event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderUpdated(orderId, newPrice);

        // Update the order
        piv.updateOrder(orderId, newPrice);

        // Verify the order was updated correctly
        (
            address storedCollateralToken,
            address storedDebtToken,
            uint256 storedCollateralAmount,
            uint256 storedRemainingCollateral,
            uint256 storedPrice,
            uint256 storedInterestRateMode
        ) = piv.orderMapping(orderId);

        // Check that only the price was updated, other fields remain the same
        assertEq(storedCollateralToken, weth, "Collateral token should remain unchanged");
        assertEq(storedDebtToken, usdc, "Debt token should remain unchanged");
        assertEq(storedCollateralAmount, orderCollateralAmount, "Collateral amount should remain unchanged");
        assertEq(storedRemainingCollateral, orderCollateralAmount, "Remaining collateral should remain unchanged");
        assertEq(storedPrice, newPrice, "Price should be updated to new value");
        assertEq(storedInterestRateMode, interestRate, "Interest rate mode should remain unchanged");

        vm.stopPrank();
    }

    function testUpdateOrderRevertNonexistentOrder() public {
        vm.startPrank(borrower);

        uint256 nonexistentOrderId = 999;
        uint256 newPrice = 2500e18;

        // Attempt to update a non-existent order
        vm.expectRevert("Order does not exist");
        piv.updateOrder(nonexistentOrderId, newPrice);

        vm.stopPrank();
    }

    function testUpdateOrderRevertInvalidPrice() public {
        vm.startPrank(borrower);

        // First, place an order to update
        uint256 orderId = piv.placeOrder(weth, 0.5 ether, usdc, 2000e18, interestRate);

        // Attempt to update with invalid price (zero)
        vm.expectRevert("Invalid price");
        piv.updateOrder(orderId, 0);

        vm.stopPrank();
    }

    function testUpdateOrderOnlyOwner() public {
        vm.startPrank(borrower);

        // Place an order as owner
        uint256 orderId = piv.placeOrder(weth, 0.5 ether, usdc, 2000e18, interestRate);

        vm.stopPrank();

        // Try to update order as non-owner
        vm.startPrank(trader);
        vm.expectRevert(); // Should revert with Ownable: caller is not the owner
        piv.updateOrder(orderId, 2500e18);
        vm.stopPrank();
    }

    function testCancelOrder() public {
        vm.startPrank(borrower);

        // First, place an order to cancel
        uint256 orderCollateralAmount = 0.5 ether;
        uint256 orderPrice = 2000e18;
        uint256 orderId = piv.placeOrder(weth, orderCollateralAmount, usdc, orderPrice, interestRate);

        // Verify the order exists before cancellation
        (address storedCollateralToken,, uint256 storedCollateralAmount,, uint256 storedPrice,) =
            piv.orderMapping(orderId);

        assertEq(storedCollateralToken, weth, "Order should exist before cancellation");
        assertEq(storedCollateralAmount, orderCollateralAmount, "Order data should be correct");
        assertEq(storedPrice, orderPrice, "Order price should be correct");

        // Expect the OrderCancelled event to be emitted
        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderCancelled(orderId);

        // Cancel the order
        piv.cancelOrder(orderId);

        // Verify the order was deleted (all fields should be zero/empty)
        (
            address cancelledCollateralToken,
            address cancelledDebtToken,
            uint256 cancelledCollateralAmount,
            uint256 cancelledRemainingCollateral,
            uint256 cancelledPrice,
            uint256 cancelledInterestRateMode
        ) = piv.orderMapping(orderId);

        assertEq(cancelledCollateralToken, address(0), "Collateral token should be zero after cancellation");
        assertEq(cancelledDebtToken, address(0), "Debt token should be zero after cancellation");
        assertEq(cancelledCollateralAmount, 0, "Collateral amount should be zero after cancellation");
        assertEq(cancelledRemainingCollateral, 0, "Remaining collateral should be zero after cancellation");
        assertEq(cancelledPrice, 0, "Price should be zero after cancellation");
        assertEq(cancelledInterestRateMode, 0, "Interest rate mode should be zero after cancellation");

        vm.stopPrank();
    }

    function testCancelOrderOnlyOwner() public {
        vm.startPrank(borrower);

        // Place an order as owner
        uint256 orderId = piv.placeOrder(weth, 0.5 ether, usdc, 2000e18, interestRate);

        vm.stopPrank();

        // Try to cancel order as non-owner
        vm.startPrank(trader);
        vm.expectRevert(); // Should revert with Ownable: caller is not the owner
        piv.cancelOrder(orderId);
        vm.stopPrank();
    }

    function testCancelNonexistentOrder() public {
        vm.startPrank(borrower);

        uint256 nonexistentOrderId = 999;

        // Cancelling a non-existent order should not revert (just deletes empty mapping)
        // Expect the OrderCancelled event to be emitted even for non-existent orders
        vm.expectEmit(true, true, true, true);
        emit IPIV.OrderCancelled(nonexistentOrderId);

        piv.cancelOrder(nonexistentOrderId);

        vm.stopPrank();
    }
}
