// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockToken} from "./MockToken.sol";

/// @notice DAI 测试网 Mock（18 位小数）。
contract MockDAI is MockToken {
    constructor() MockToken("Mock Dai Stablecoin", "DAI", 18) {}
}
