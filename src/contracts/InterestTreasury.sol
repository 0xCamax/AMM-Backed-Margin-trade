// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RateConfig} from "../libraries/InterestLib.sol";
import {Math} from "../libraries/utils/Math.sol";

contract InterestTreasury is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    address public immutable manager;

    uint256 public totalAssets;

    struct Loan {
        address borrower;
        uint256 principal;
        uint256 timestamp;
        uint256 repaid;
    }

    Loan[] public loans;
    RateConfig public rateConfig;

    modifier onlyManager() {
        require(msg.sender == manager, "Not authorized");
        _;
    }

    constructor(address _asset) ERC20("Interest-Bearing LP Share", "IBLP") {
        require(_asset != address(0), "Invalid asset");

        asset = IERC20(_asset);
        manager = msg.sender;
        rateConfig = RateConfig(5, 5, 1);
    }

    // -----------------------------
    // 💰 Deposit / Withdraw
    // -----------------------------
    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");
        _accrueInterest();

        uint256 pool = totalAssets;
        uint256 supply = totalSupply();

        //asset.safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = (supply == 0 || pool == 0)
            ? amount
            : (amount * supply) / pool;

        totalAssets += amount;
        _mint(msg.sender, shares);
    }

    function withdraw(uint256 shares) external {
        require(shares > 0, "Zero shares");
        _accrueInterest();

        uint256 pool = totalAssets;
        uint256 supply = totalSupply();
        uint256 amount = (shares * pool) / supply;

        totalAssets -= amount;
        _burn(msg.sender, shares);
        //asset.safeTransfer(msg.sender, amount);
    }

    // -----------------------------
    // 🧾 Borrow / Repay / Donate
    // -----------------------------
    function borrow(uint256 amount) external onlyManager {
        require(amount > 0, "Zero amount");
        require(
            amount <= asset.balanceOf(address(this)),
            "Insufficient liquidity"
        );

        _accrueInterest();

        loans.push(
            Loan({
                borrower: msg.sender,
                principal: amount,
                timestamp: block.timestamp,
                repaid: 0
            })
        );

        //asset.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 loanId, uint256 amount) external {
        require(loanId < loans.length, "Invalid loan");
        Loan memory loan = loans[loanId];
        require(amount > 0, "Zero repay");
        require(
            loan.repaid < loan.principal + interestOwed(loanId),
            "Already repaid"
        );

        //asset.safeTransferFrom(msg.sender, address(this), amount);

        loan.repaid += amount;
        totalAssets += amount;

        loans[loanId] = loan;

        emit Repaid(msg.sender, loanId, amount);
    }

    function donate(uint256 amount) external {
        require(amount > 0, "Zero donation");
        //asset.safeTransferFrom(msg.sender, address(this), amount);
        _accrueInterest();
    }

    function _accrueInterest() internal {
        uint256 actual = asset.balanceOf(address(this));
        if (actual > totalAssets) {
            uint256 profit = actual - totalAssets;
            totalAssets = actual;
            emit InterestAccrued(profit);
        }
    }

    // -----------------------------
    // 📈 Interest Calculations
    // -----------------------------
    function interestOwed(uint256 loanId) public view returns (uint256) {
        require(loanId < loans.length, "Invalid loan");
        Loan memory loan = loans[loanId];

        uint256 elapsed = block.timestamp - loan.timestamp;
        uint256 util = utilization(); // 0 to 1e18

        int256 rate = rateConfig.getPerSecondRate(int256(util)); // scaled by 1e18
        uint256 interest = (loan.principal * uint256(rate) * elapsed) / 1e18;

        return interest;
    }

    function utilization() public view returns (uint256) {
        uint256 borrowed;
        for (uint256 i = 0; i < loans.length; i++) {
            Loan memory loan = loans[i];
            uint256 owed = loan.principal + interestOwed(i);
            if (loan.repaid < owed) {
                borrowed += (owed - loan.repaid);
            }
        }

        uint256 pool = totalAssets == 0 ? 1 : totalAssets;
        return (borrowed * 1e18) / pool;
    }

    // -----------------------------
    // 🔍 Views
    // -----------------------------
    function getLoan(uint256 loanId) external view returns (Loan memory) {
        return loans[loanId];
    }

    event Borrowed(address indexed borrower, uint256 amount);
    event Repaid(address indexed payer, uint256 loanId, uint256 amount);
    event InterestAccrued(uint256 amount);
}
