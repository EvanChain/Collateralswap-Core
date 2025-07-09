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
        assertEq(IERC20(aWeth).balanceOf(address(piv)), collateralAmount, "PIV should have collateralAmount aWETH after migration");

        vm.stopPrank();
    }

    function testPlaceOrder() public 
    {
        
    }
}
