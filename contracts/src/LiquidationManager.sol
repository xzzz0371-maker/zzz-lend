// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ILiquidationManager {
    /// @notice Returns the collateral value (WAD) a liquidator may seize for covering `debtToCoverWad`,
    ///         capped at the total collateral value. Applies the liquidation bonus.
    function computeSeizeValue(uint256 collateralValueWad, uint256 debtToCoverWad, uint256 bonusWad)
        external
        pure
        returns (uint256);
}

contract LiquidationManager is ILiquidationManager {
    uint256 public constant WAD = 1e18;

    function computeSeizeValue(uint256 collateralValueWad, uint256 debtToCoverWad, uint256 bonusWad)
        external
        pure
        returns (uint256)
    {
        uint256 seize = debtToCoverWad * (WAD + bonusWad) / WAD;
        if (seize > collateralValueWad) seize = collateralValueWad;
        return seize;
    }
}
