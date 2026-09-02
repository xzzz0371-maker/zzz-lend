// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockToken} from "./MockToken.sol";

/// @notice wstETH 测试网 Mock（18 位小数）。价格与抵押价值由预言机决定，与真实 wstETH 的换汇率解耦。
contract MockWstETH is MockToken {
    constructor() MockToken("Mock Wrapped Staked ETH", "wstETH", 18) {}
}
