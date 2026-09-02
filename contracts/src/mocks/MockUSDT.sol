// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockToken} from "./MockToken.sol";

/// @notice USDT 测试网 Mock（6 位小数）。
contract MockUSDT is MockToken {
    constructor() MockToken("Mock Tether USD", "USDT", 6) {}
}
