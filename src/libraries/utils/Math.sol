// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Math {
    // Fixed point precision (18 decimals)
    uint256 internal constant PRECISION = 1e18;

    // Natural log of 10 * PRECISION for base conversion
    uint256 internal constant LN10 = 2302585092994045684; // ln(10) * 1e18

    /**
     * @dev Calculates natural logarithm using Taylor series approximation
     * Input should be in fixed point format (multiplied by PRECISION)
     * Returns ln(x) * PRECISION
     */
    function ln(uint256 x) internal pure returns (int256) {
        require(x > 0, "ln: input must be positive");

        if (x == PRECISION) return 0; // ln(1) = 0

        int256 result = 0;

        // Normalize x to range [1, 2) for better convergence
        int256 shift = 0;
        uint256 normalized = x;

        while (normalized >= 2 * PRECISION) {
            normalized = normalized / 2;
            shift++;
        }

        while (normalized < PRECISION) {
            normalized = normalized * 2;
            shift--;
        }

        // Taylor series: ln(1+y) = y - y²/2 + y³/3 - y⁴/4 + ...
        // where y = normalized - 1
        int256 y = int256(normalized) - int256(PRECISION);
        int256 y_pow = y;

        // Calculate first 10 terms of Taylor series
        for (uint256 i = 1; i <= 10; i++) {
            if (i % 2 == 1) {
                result += y_pow / int256(i);
            } else {
                result -= y_pow / int256(i);
            }
            y_pow = (y_pow * y) / int256(PRECISION);
        }

        // Add back the shift factor: ln(2^shift) = shift * ln(2)
        result += shift * 693147180559945309; // ln(2) * 1e18

        return result;
    }

    /**
     * @dev Calculates log base 10
     * Returns log10(x) * PRECISION
     */
    function log10(uint256 x) internal pure returns (int256) {
        int256 ln_x = ln(x);
        return (ln_x * int256(PRECISION)) / int256(LN10);
    }

    /**
     * @dev Helper function to convert regular number to fixed point
     */
    function toFixedPoint(uint256 value) public pure returns (uint256) {
        return value * PRECISION;
    }

    /**
     * @dev Helper function to convert fixed point back to regular number
     */
    function fromFixedPoint(int256 value) public pure returns (int256) {
        return value / int256(PRECISION);
    }
}
