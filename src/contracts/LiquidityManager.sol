// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RateConfig} from "../libraries/InterestLib.sol";
import {Math} from "../libraries/utils/Math.sol";

contract LiquidityManager is ERC20 {
    using SafeERC20 for IERC20;

    struct Loan {
        uint256 principal;
        uint256 borrowIndex;
        Repaid repaid;
    }

    struct Repaid {
        uint256 principal;
        uint256 interest;
    }

    struct PoolState {
        uint256 borrowed;
        uint256 supplied;
    }

    IERC20 public immutable asset;
    address public immutable manager;

    PoolState public totalAssets;

    // Global interest tracking - much more gas efficient
    uint256 public borrowIndex;
    uint256 public lastUpdateTime;

    mapping(address => Loan) public loans;
    RateConfig public rateConfig;

    modifier onlyManager() {
        require(msg.sender == manager, "Not authorized");
        _;
    }

    constructor(
        address _asset,
        address _manager
    ) ERC20("Interest-Bearing LP Share", "IBLP") {
        require(_asset != address(0), "Invalid asset");

        asset = IERC20(_asset);
        manager = _manager;
        rateConfig = RateConfig(5, 5, 1);
        lastUpdateTime = block.timestamp;
        borrowIndex = 1e18;
    }

    // -----------------------------
    // 💰 Deposit / Withdraw
    // -----------------------------
    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");
        _updateBorrowIndex();

        uint256 pool = totalAssets.supplied;
        uint256 supply = totalSupply();

        asset.safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares = (supply == 0 || pool == 0)
            ? amount
            : (amount * supply) / pool;

        totalAssets.supplied += amount;
        _mint(msg.sender, shares);
    }

    function withdraw(uint256 shares) external {
        require(shares > 0, "Zero shares");
        _updateBorrowIndex();

        uint256 pool = totalAssets.supplied;
        uint256 supply = totalSupply();
        uint256 amount = (shares * pool) / supply;

        totalAssets.supplied -= amount;
        _burn(msg.sender, shares);
        asset.safeTransfer(msg.sender, amount);
    }

    // -----------------------------
    // 🧾 Borrow / Repay / Donate
    // -----------------------------
    function borrow(uint256 amount, address borrower) external onlyManager {
        require(amount > 0, "Zero amount");
        require(
            amount <= asset.balanceOf(address(this)),
            "Insufficient liquidity"
        );

        _updateBorrowIndex();

        Loan storage loan = loans[borrower];

        if (loan.principal > 0) {
            // Settle existing loan first by calculating accrued interest
            uint256 accruedInterest = _calculateAccruedInterest(
                loan.principal,
                loan.borrowIndex
            );

            // Add accrued interest to the pool
            totalAssets.supplied += accruedInterest;

            // Update loan with new principal and reset index
            loan.principal += amount + accruedInterest;
            loan.borrowIndex = borrowIndex;
        } else {
            // New loan
            loans[borrower] = Loan({
                principal: amount,
                borrowIndex: borrowIndex,
                repaid: Repaid(0, 0)
            });
        }

        totalAssets.borrowed += amount;
        asset.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    function repay(address loanId, uint256 amount) external {
        require(amount > 0, "Zero repay");
        require(loans[loanId].principal != 0, "Invalid loan");

        _updateBorrowIndex();

        Loan storage loan = loans[loanId];

        // Calculate total debt (principal + accrued interest)
        uint256 accruedInterest = _calculateAccruedInterest(
            loan.principal,
            loan.borrowIndex
        );
        uint256 totalDebt = loan.principal +
            accruedInterest -
            loan.repaid.principal -
            loan.repaid.interest;

        require(amount <= totalDebt, "Repay amount exceeds debt");

        asset.safeTransferFrom(msg.sender, address(this), amount);

        uint256 remainingAmount = amount;
        uint256 interestPayment = 0;
        uint256 principalPayment = 0;

        // Pay interest first
        uint256 _interestOwed = accruedInterest - loan.repaid.interest;
        if (remainingAmount > 0 && _interestOwed > 0) {
            interestPayment = remainingAmount > _interestOwed
                ? _interestOwed
                : remainingAmount;
            remainingAmount -= interestPayment;
            totalAssets.supplied += interestPayment; // Interest goes to pool
        }

        // Then pay principal
        if (remainingAmount > 0) {
            principalPayment = remainingAmount;
            totalAssets.borrowed -= principalPayment;
        }

        loan.repaid.interest += interestPayment;
        loan.repaid.principal += principalPayment;

        // Update loan principal and index if there's still debt
        if (
            loan.principal + accruedInterest >
            loan.repaid.principal + loan.repaid.interest
        ) {
            loan.principal =
                loan.principal +
                accruedInterest -
                loan.repaid.principal -
                loan.repaid.interest;
            loan.borrowIndex = borrowIndex;
            loan.repaid = Repaid(0, 0); // Reset repaid amounts since we normalized the principal
        }

        emit LoanRepaid(msg.sender, loanId, amount);
    }

    function donate(uint256 amount) external {
        require(amount > 0, "Zero donation");
        asset.safeTransferFrom(msg.sender, address(this), amount);
        _updateBorrowIndex();
        totalAssets.supplied += amount;
    }

    // -----------------------------
    // 🔧 Internal Functions
    // -----------------------------
    function _updateBorrowIndex() internal {
        if (block.timestamp == lastUpdateTime || totalAssets.borrowed == 0) {
            return;
        }

        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        uint256 util = utilization();

        if (util > 0) {
            int256 rate = rateConfig.getPerSecondRate(int256(util));

            if (rate > 0) {
                // Update the global borrow index
                uint256 interestFactor = 1e18 + (uint256(rate) * timeElapsed);
                borrowIndex = (borrowIndex * interestFactor) / 1e18;

                // Calculate total interest accrued
                uint256 totalInterest = (totalAssets.borrowed *
                    (interestFactor - 1e18)) / 1e18;
                emit InterestAccrued(totalInterest);
            }
        }

        lastUpdateTime = block.timestamp;
    }

    function _calculateAccruedInterest(
        uint256 principal,
        uint256 loanBorrowIndex
    ) internal view returns (uint256) {
        if (loanBorrowIndex == 0) return 0;

        // Calculate current index
        uint256 currentIndex = borrowIndex;

        if (block.timestamp > lastUpdateTime && totalAssets.borrowed > 0) {
            uint256 timeElapsed = block.timestamp - lastUpdateTime;
            uint256 util = utilization();

            if (util > 0) {
                int256 rate = rateConfig.getPerSecondRate(int256(util));
                if (rate > 0) {
                    uint256 interestFactor = 1e18 +
                        (uint256(rate) * timeElapsed);
                    currentIndex = (borrowIndex * interestFactor) / 1e18;
                }
            }
        }

        // Interest = principal * (currentIndex - loanIndex) / loanIndex
        if (currentIndex > loanBorrowIndex) {
            return
                (principal * (currentIndex - loanBorrowIndex)) /
                loanBorrowIndex;
        }

        return 0;
    }

    // -----------------------------
    // 📈 Interest Calculations
    // -----------------------------
    function interestOwed(address loanId) public view returns (uint256) {
        Loan memory loan = loans[loanId];
        require(loan.principal != 0, "Invalid loan");

        uint256 accruedInterest = _calculateAccruedInterest(
            loan.principal,
            loan.borrowIndex
        );
        return
            accruedInterest > loan.repaid.interest
                ? accruedInterest - loan.repaid.interest
                : 0;
    }

    function utilization() public view returns (uint256) {
        if (totalAssets.supplied == 0) return 0;
        return (totalAssets.borrowed * 1e18) / totalAssets.supplied;
    }

    // -----------------------------
    // 🔍 Views
    // -----------------------------
    function getLoan(address loanId) external view returns (Loan memory) {
        return loans[loanId];
    }

    function getTotalOwed(address loanId) external view returns (uint256) {
        Loan memory loan = loans[loanId];
        if (loan.principal == 0) return 0;

        uint256 accruedInterest = _calculateAccruedInterest(
            loan.principal,
            loan.borrowIndex
        );
        uint256 totalOwed = loan.principal + accruedInterest;
        uint256 totalRepaid = loan.repaid.principal + loan.repaid.interest;

        return totalOwed > totalRepaid ? totalOwed - totalRepaid : 0;
    }

    function getCurrentBorrowIndex() external view returns (uint256) {
        if (block.timestamp == lastUpdateTime || totalAssets.borrowed == 0) {
            return borrowIndex;
        }

        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        uint256 util = utilization();

        if (util > 0) {
            int256 rate = rateConfig.getPerSecondRate(int256(util));
            if (rate > 0) {
                uint256 interestFactor = 1e18 + (uint256(rate) * timeElapsed);
                return (borrowIndex * interestFactor) / 1e18;
            }
        }

        return borrowIndex;
    }

    function optionPayout(uint256 amount) external onlyManager {
        require(amount > 0, "Zero payout");
        require(amount <= asset.balanceOf(address(this)), "Insufficient funds");

        _updateBorrowIndex();

        require(amount <= totalAssets.supplied, "Amount exceeds supplied");
        totalAssets.supplied -= amount;

        asset.safeTransfer(msg.sender, amount);
    }

    event Borrowed(address indexed borrower, uint256 amount);
    event LoanRepaid(address indexed payer, address loanId, uint256 amount);
    event InterestAccrued(uint256 amount);
}
