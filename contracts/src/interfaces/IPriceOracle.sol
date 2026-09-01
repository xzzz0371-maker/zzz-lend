// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IPriceOracle {
    /// @notice Returns the price of `asset` in USD with 8 decimals.
    function getAssetPrice(address asset) external view returns (uint256);

    /// @notice Returns true if the last price update for `asset` was flagged as anomalous (deviation > threshold).
    function isPriceAnomalous(address asset) external view returns (bool);
}
