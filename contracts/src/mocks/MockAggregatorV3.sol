// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IAggregatorV3 {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract MockAggregatorV3 is IAggregatorV3 {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public dec;

    function setData(int256 _answer, uint256 _updatedAt, uint8 _decimals) external {
        answer = _answer;
        updatedAt = _updatedAt;
        dec = _decimals;
    }

    function decimals() external view returns (uint8) {
        return dec;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, answer, 0, updatedAt, 0);
    }
}
