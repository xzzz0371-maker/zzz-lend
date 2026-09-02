// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockToken} from "./MockToken.sol";

/// @notice WBTC 测试网 Mock（8 位小数）。
contract MockWBTC is MockToken {
    constructor() MockToken("Mock Wrapped Bitcoin", "WBTC", 8) {}
}
