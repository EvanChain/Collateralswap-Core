// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test} from "forge-std/Test.sol";
import {PIV} from "../src/PIV.sol";
import {IAaveV3PoolMinimal} from "../src/extensions/IAaveV3PoolMinimal.sol";

contract FrokPiv is Test {
    address constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; // Aave V3 Pool on Ethereum Mainnet
    address constant AAVE_V3_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        vm.createSelectFork(MAINNET_RPC_URL);
    }

    function testMigrateFromAave() public {
        IAaveV3PoolMinimal aavePool = IAaveV3PoolMinimal(AAVE_V3_POOL);

        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address aWeth = aavePool.getReserveData(weth).aTokenAddress;

        address user = vm.addr(1);
        // Ensure the user has Collateral tokens
        deal(weth, user, 1 ether);
        uint256 interestRate = 2; // Float interest rate mode

        vm.startPrank(user);
        //create the vault
        PIV piv = new PIV(AAVE_V3_POOL, AAVE_V3_ADDRESS_PROVIDER);

        uint256 debtAmount = 1000e6; // 1000 USDC(debt amount)
        // borrow USDC from Aave
        IERC20(weth).approve(address(aavePool), 1 ether); // Approve WETH for supply
        aavePool.supply(weth, 1 ether, user, 0); // Supply 1 WETH as collateral
        aavePool.borrow(usdc, debtAmount, interestRate, 0, user); // Borrow 1000 USDC
        assertEq(IERC20(usdc).balanceOf(user), debtAmount, "User should have 1000 USDC");
        assertEq(IERC20(aWeth).balanceOf(user), 1 ether, "User should have 1 aWETH");
        // collateralToken.approve(address(piv), collateralAmount);
        // piv.migrateFromAave(collateralToken, collateralAmount, interestMode);
        IERC20(aWeth).approve(address(piv), 1 ether);
        piv.migrateFromAave(IERC20(aWeth), 1 ether, IERC20(usdc), debtAmount, interestRate);
        assertEq(IERC20(aWeth).balanceOf(user), 0, "User should have 0 aWETH after migration");
        assertEq(IERC20(aWeth).balanceOf(address(piv)), 1 ether, "PIV should have 1 aWETH after migration");

        vm.stopPrank();
    }
}
