#!/usr/bin/env bash
# ZZZ Lend Sepolia 端到端测试（cast 版，已在本机 Anvil 验证通过）
# 用法（先执行 Deploy.s.sol 完成部署，或已写好 deployments/sepolia.json）：
#   bash script/e2e_sepolia.sh
# 依赖环境变量（见 .env）：
#   RPC_URL=SEPOLIA_RPC_URL
#   DEPLOYER_KEY / USER_A_KEY / USER_B_KEY （测试网专用私钥）
#   ADMIN=TESTNET_ADMIN（缺省为部署者）
set -euo pipefail

RPC=${RPC_URL:?need RPC_URL}
J() { python -c "import json,sys;print(json.load(open('deployments/sepolia.json'))['$1'])"; }
POOL=$(J lendingPool)
USDC=$(J usdc)
MOCK=$(J mockOracle)
CHAIN=$(J oracle)
SWITCH=$(J switchableOracle)
ADMIN=${ADMIN:-$(cast wallet address --private-key "$DEPLOYER_KEY")}
# 切换模式的人需持有 PAUSER；设价的人需持有 PARAM_ADMIN。部署者两者都持有。
PAUSER_KEY=${PAUSER_KEY:-$DEPLOYER_KEY}
ETH=0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
MAX=115792089237316195423570985008687907853269984665640564039457584007913129639935

A=$(cast wallet address --private-key "$USER_A_KEY")
B=$(cast wallet address --private-key "$USER_B_KEY")
LIQ=${LIQUIDATOR_KEY:-$DEPLOYER_KEY}
L=$(cast wallet address --private-key "$LIQ")

say() { echo; echo "===== $1 ====="; }
send() { cast send "$@" --rpc-url "$RPC" --json 2>/dev/null | python -c "import json,sys; d=json.load(sys.stdin); print(d['status'], d['transactionHash'])"; }
# 取 cast 输出的第一个数字（去掉 [标注] 与多余行）
p0() { python -c "import sys; print(sys.stdin.read().split()[0])"; }

say "0. 测试用户"
echo "A=$A  B=$B  L=$L  ADMIN=$ADMIN"

say "1. A supply 1000 USDC"
send $USDC "faucet(uint256)" 10000000000 --private-key "$USER_A_KEY"
send $USDC "approve(address,uint256)" $POOL $MAX --private-key "$USER_A_KEY"
send $POOL "supply(uint256)" 1000000000 --private-key "$USER_A_KEY"

say "1b. deployer 补足流动性（支撑清算演示）"
send $USDC "faucet(uint256)" 200000000000 --private-key "$DEPLOYER_KEY"
send $USDC "approve(address,uint256)" $POOL $MAX --private-key "$DEPLOYER_KEY"
send $POOL "supply(uint256)" 200000000000 --private-key "$DEPLOYER_KEY"

say "2. B supply 10 ETH collateral"
send $POOL "supplyCollateral()" --value 10000000000000000000 --private-key "$USER_B_KEY"

say "3. B borrow @ tier 3 (70% LTV)"
MAXB=$(cast call $POOL "maxBorrowable(address,uint256)(uint256)" $B 3 --rpc-url "$RPC" | awk "{print \$1}")
send $POOL "borrow(uint256,uint256)" "$MAXB" 3 --private-key "$USER_B_KEY"

say "4. 检查 B 状态"
echo "HF    = $(cast call $POOL "getUserHealthFactor(address)(uint256)" $B --rpc-url "$RPC")"
echo "debt  = $(cast call $POOL "getDebt(address)(uint256)" $B --rpc-url "$RPC")"
echo "collv = $(cast call $POOL "getCollateralValue(address)(uint256)" $B --rpc-url "$RPC")"

say "5. B 部分还款"
send $USDC "approve(address,uint256)" $POOL $MAX --private-key "$USER_B_KEY"
send $POOL "repay(uint256)" $((MAXB / 10)) --private-key "$USER_B_KEY"

say "6. A 提取部分存款"
SHARES=$(cast call $POOL "getUserPosition(address)(uint256,uint256,uint256,uint256,uint256,uint256,bool)" $A --rpc-url "$RPC" | p0)
send $POOL "withdraw(uint256)" "$((SHARES / 2))" --private-key "$USER_A_KEY"

say "7. 模拟清算：SwitchableOracle 切到可设价模式，ETH -30%"
send $SWITCH "enableSettable()" --private-key "$PAUSER_KEY"
send $SWITCH "setPrice(address,uint256)" $ETH 210000000000 --private-key "$DEPLOYER_KEY"
send $SWITCH "setPrice(address,uint256)" $USDC 100000000 --private-key "$DEPLOYER_KEY"
HF=$(cast call $POOL "getUserHealthFactor(address)(uint256)" $B --rpc-url "$RPC")
echo "after -30%, B HF=$HF liquidatable=$(cast call $POOL "isLiquidatable(address)(bool)" $B --rpc-url "$RPC")"
if [ "$(cast call $POOL "isLiquidatable(address)(bool)" $B --rpc-url "$RPC")" = "true" ]; then
  send $USDC "faucet(uint256)" 10000000000 --private-key "$LIQ"
  send $USDC "approve(address,uint256)" $POOL $MAX --private-key "$LIQ"
  send $POOL "liquidate(address,uint256,uint256)" $B 100000000000 0 --private-key "$LIQ"
  echo "new HF = $(cast call $POOL "getUserHealthFactor(address)(uint256)" $B --rpc-url "$RPC")"
fi
send $SWITCH "disableSettable()" --private-key "$PAUSER_KEY"

say "8. 资金守恒检查"
LHS=$(cast call $POOL "cash()(uint256)" --rpc-url "$RPC" | p0)
LHS2=$(cast call $POOL "getTotalBorrows()(uint256)" --rpc-url "$RPC" | p0)
RHS=$(cast call $POOL "getTotalSupply()(uint256)" --rpc-url "$RPC" | p0)
RHS2=$(cast call $POOL "totalReserve()(uint256)" --rpc-url "$RPC" | p0)
RHS3=$(cast call $POOL "treasuryAccrued()(uint256)" --rpc-url "$RPC" | p0)
echo "cash+borrows = $((LHS + LHS2))"
echo "supply+reserve+treasury = $((RHS + RHS2 + RHS3))"
echo "E2E done."
