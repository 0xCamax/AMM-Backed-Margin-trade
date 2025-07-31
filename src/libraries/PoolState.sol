// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCast} from "./utils/SafeCast.sol";

/// @dev Two `int128` values packed into a single `int256` where the upper 128 bits represent the borrowed
/// and the lower 128 bits represent the supplied.
type PoolState is int256;

using {add as +, sub as -, eq as ==, neq as !=} for PoolState global;
using PoolStateLibrary for PoolState global;
using SafeCast for int256;

function toPoolState(
    int128 _borrowed,
    int128 _supplied
) pure returns (PoolState _poolState) {
    assembly ("memory-safe") {
        _poolState := or(
            shl(128, _borrowed),
            and(sub(shl(128, 1), 1), _supplied)
        )
    }
}

function add(PoolState a, PoolState b) pure returns (PoolState) {
    int256 res0;
    int256 res1;
    assembly ("memory-safe") {
        let a0 := sar(128, a)
        let a1 := signextend(15, a)
        let b0 := sar(128, b)
        let b1 := signextend(15, b)
        res0 := add(a0, b0)
        res1 := add(a1, b1)
    }
    return toPoolState(res0.toInt128(), res1.toInt128());
}

function sub(PoolState a, PoolState b) pure returns (PoolState) {
    int256 res0;
    int256 res1;
    assembly ("memory-safe") {
        let a0 := sar(128, a)
        let a1 := signextend(15, a)
        let b0 := sar(128, b)
        let b1 := signextend(15, b)
        res0 := sub(a0, b0)
        res1 := sub(a1, b1)
    }
    return toPoolState(res0.toInt128(), res1.toInt128());
}

function eq(PoolState a, PoolState b) pure returns (bool) {
    return PoolState.unwrap(a) == PoolState.unwrap(b);
}

function neq(PoolState a, PoolState b) pure returns (bool) {
    return PoolState.unwrap(a) != PoolState.unwrap(b);
}

/// @notice Library for getting the borrowed and supplied amounts from the PoolState type
library PoolStateLibrary {
    /// @notice A PoolState of 0
    PoolState public constant ZERO_DELTA = PoolState.wrap(0);

    function borrowed(PoolState s) internal pure returns (int128 _borrowed) {
        assembly ("memory-safe") {
            _borrowed := sar(128, s)
        }
    }

    function supplied(PoolState s) internal pure returns (int128 _supplied) {
        assembly ("memory-safe") {
            _supplied := signextend(15, s)
        }
    }

    function utilization(PoolState s) internal pure returns (int256) {
        if(s.supplied() == 0){
            return 0;
        }
        return (s.borrowed() * 1e18) / s.supplied();
    }

    function addBorrow(
        PoolState s,
        int128 delta
    ) internal pure returns (PoolState) {
        s = toPoolState(s.borrowed() + delta, s.supplied());
        return s;
    }

    function addSupply(
        PoolState s,
        int128 delta
    ) internal pure returns (PoolState) {
        s = toPoolState(s.borrowed(), s.supplied() + delta);
        return s;
    }

    
}
