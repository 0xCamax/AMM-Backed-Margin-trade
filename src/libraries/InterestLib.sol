// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "./utils/Math.sol";

struct RateConfig {
    int256 sharpness;
    int256 baseRate;
    int256 limit;
}

using InterestRateLibrary for RateConfig global;

library InterestRateLibrary {
    uint256 constant SECONDS_PER_YEAR = 365 days; // 31,536,000 seconds
    uint256 constant HUNDRED_PERCENT = 1e18;

    /**
     * @dev Interest Rate Model: (log10(utilization + 1) - log10(-utilization + 1 + limit)) / sharpness + baseRate
     * Input utilization should be in fixed point format (multiplied by PRECISION)
     * Returns result * PRECISION
     */
    function borrowRate(
        RateConfig storage config,
        int256 utilization
    ) internal view returns (int256) {
        int256 base = config.baseRate * 1e16;
        // Calculate utilization + 1
        int256 term1_input = utilization + int256(Math.PRECISION);
        require(term1_input > 0, "x + 1 must be positive");

        // Calculate -utilization + 1.0001
        int256 term2_input = -utilization + 1 ether + config.limit; // 1.0001 * 1e18
        require(term2_input > 0, "-utilization + 1.0001 must be positive");

        // Calculate log10(utilization + 1)
        int256 log1 = Math.log10(uint256(term1_input));

        // Calculate log10(-utilization + 1.0001)
        int256 log2 = Math.log10(uint256(term2_input));

        // Calculate (log1 - log2) / 5
        int256 diff = (log1 - log2) / config.sharpness;

        // Add baseRate
        int256 result = diff + base;

        return result;
    }

    /**
     * @dev Convert annual interest rate to per-second rate
     * Formula: perSecondRate = (annualRate / SECONDS_PER_YEAR)
     * For compound interest: perSecondRate = (1 + annualRate)^(1/SECONDS_PER_YEAR) - 1
     * This implementation uses simple interest per second for gas efficiency
     */
    function getPerSecondRate(
        RateConfig storage config,
        int256 utilization
    ) internal view returns (int256) {
        int256 annualRate = borrowRate(config, utilization);
        return annualRate / int256(SECONDS_PER_YEAR);
    }
}
