// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Treasury for Binary Options protocol
/// LPs deposit USDC and receive shares; protocol pays winners from the pool
contract BinaryOptionsTreasury is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset; // e.g. USDC
    address public manager;        // BinaryOptionsManager

    modifier onlyManager() {
        require(msg.sender == manager, "Not authorized");
        _;
    }

    constructor(address _asset, address _manager)
        ERC20("Binary Options LP Share", "BOLP")
    {
        require(_asset != address(0), "Invalid asset");
        require(_manager != address(0), "Invalid manager");

        asset = IERC20(_asset);
        manager = _manager;
    }

    /// @notice Total pool value in underlying asset
    function totalPool() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice LP deposits funds to provide liquidity
    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");

        uint256 pool = totalPool();
        uint256 supply = totalSupply();

        // Transfer underlying
        asset.safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares;
        if (supply == 0 || pool == 0) {
            shares = amount; // 1:1 for first deposit
        } else {
            shares = (amount * supply) / pool;
        }

        _mint(msg.sender, shares);
    }

    /// @notice LP withdraws proportional share
    function withdraw(uint256 shares) external {
        require(shares > 0, "Zero shares");

        uint256 pool = totalPool();
        uint256 supply = totalSupply();

        uint256 amount = (shares * pool) / supply;

        _burn(msg.sender, shares);
        asset.safeTransfer(msg.sender, amount);
    }

    /// @notice Pay out winners (only manager can call)
    function payWinner(address winner, uint256 amount) external onlyManager {
        require(amount > 0, "Zero payout");
        asset.safeTransfer(winner, amount);
    }

    /// @notice Collect losing stakes (adds to pool)
    function collectStake(uint256 amount) external onlyManager {
        // Manager must transfer stake first
        require(asset.balanceOf(address(this)) >= totalPool() + amount, "Stake not received");
    }
}
