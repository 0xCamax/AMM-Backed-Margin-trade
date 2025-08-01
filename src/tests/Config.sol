// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LiquidityManager} from "../contracts/LiquidityManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 amount) external;
}

contract Config {
    IWETH internal constant WETH =
        IWETH(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    LiquidityManager public treasury;

    constructor() payable {
        WETH.deposit{value: msg.value}();
        WETH.transfer(msg.sender, msg.value);
        treasury = new LiquidityManager(address(WETH), msg.sender);
    }
}
