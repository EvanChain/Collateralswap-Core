// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAaveV3PoolMinimal} from "./extensions/IAaveV3PoolMinimal.sol";
import {IAaveV3FlashLoanReceiver} from "./extensions/IAaveV3FlashLoanReceiver.sol";
import {console} from "forge-std/console.sol";

contract PIV is IAaveV3FlashLoanReceiver, Ownable {
    using SafeERC20 for IERC20;

    address public constant POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address public constant ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    constructor() Ownable(msg.sender) {}

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
        IAaveV3PoolMinimal(POOL).borrow(asset, newDebtAmount, interestMode, 0, address(this));
        IERC20(asset).safeIncreaseAllowance(POOL, amount + premium);
        console.log("New debt amount:", newDebtAmount);
        return true;
    }

    // interestMode 1 for Stable, 2 for Variable
    function migrateFromAave(
        IERC20 collateralToken,
        uint256 collateralAmount,
        IERC20 debtToken,
        uint256 debtAmount,
        uint256 interestRateMode
    ) external onlyOwner {
        bytes memory params = abi.encode(msg.sender, collateralToken, collateralAmount, interestRateMode);
        IAaveV3PoolMinimal(POOL).flashLoanSimple(address(this), address(debtToken), debtAmount, params, 0);
    }
}
