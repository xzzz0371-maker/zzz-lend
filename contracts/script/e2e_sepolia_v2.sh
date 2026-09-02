#!/usr/bin/env bash
# ZZZ Lend Sepolia V2 multi-asset E2E (cast, text-receipt judging).
# Use fresh actor accounts (funded by deployer) for idempotent, deterministic flows.
# Env: RPC_URL, DEPLOYER_KEY, [ADMIN]
set -uo pipefail
RPC=${RPC_URL:?need RPC_URL}
J() { python -c "import json,sys;print(json.load(open('deployments/sepolia.json'))['$1'])"; }
POOL=$(J lendingPool); USDC=$(J usdc); USDT=$(J usdt); DAI=$(J dai)
WSTETH=$(J wsteth); WBTC=$(J wbtc); SWITCH=$(J switchableOracle)
DEP=${DEPLOYER_KEY:?need DEPLOYER_KEY}
DEPS=$(cast wallet address --private-key "$DEP")
ETH=0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
MAX=115792089237316195423570985008687907853269984665640564039457584007913129639935
say() { echo; echo "===== $1 ====="; }

send() { # text-receipt judging (no --json; robust under pipes)
  local tries=0 out
  while true; do
    out=$(cast send "$@" --rpc-url "$RPC" 2>&1)
    rc=$?
    if [ $rc -eq 0 ] && echo "$out" | grep -q "1 (success)"; then
      echo "$out" | grep -E "transactionHash" | head -1
      return 0
    fi
    tries=$((tries+1))
    if [ $tries -ge 5 ]; then echo "TX FAIL rc=$rc: $*"; echo "$out" | grep -iE "revert|error|insufficient|nonce|replacement" | head -3; return 1; fi
    sleep 4
  done
}
call() { cast call "$@" --rpc-url "$RPC" 2>/dev/null | python -c "import sys;print(sys.stdin.read().split()[0])"; }

# fresh accounts
keyA=$(cast wallet new --json 2>/dev/null | python -c "import json,sys;print(json.load(sys.stdin)['data'][0]['private_key'])")
keyL=$(cast wallet new --json 2>/dev/null | python -c "import json,sys;print(json.load(sys.stdin)['data'][0]['private_key'])")
A=$(cast wallet address --private-key "$keyA")
L=$(cast wallet address --private-key "$keyL")
say "0. 账户：deployer=$DEPS（admin） mainA=$A liquidator=$L"
cast send "$A" --value 60000000000000000 --private-key "$DEP" --rpc-url "$RPC" 2>/dev/null | grep -E "transactionHash" | head -1
cast send "$L" --value 40000000000000000 --private-key "$DEP" --rpc-url "$RPC" 2>/dev/null | grep -E "transactionHash" | head -1

say "1. SwitchableOracle 可设价模式 + 统一价格（幂等）"
send $SWITCH "enableSettable()" --private-key "$DEP"
send $SWITCH "setPrice(address,uint256)" $ETH 300000000000 --private-key "$DEP"
send $SWITCH "setPrice(address,uint256)" $WSTETH 300000000000 --private-key "$DEP"
send $SWITCH "setPrice(address,uint256)" $WBTC 10000000000000 --private-key "$DEP"
send $SWITCH "setPrice(address,uint256)" $USDC 100000000 --private-key "$DEP"
send $SWITCH "setPrice(address,uint256)" $USDT 100000000 --private-key "$DEP"
send $SWITCH "setPrice(address,uint256)" $DAI 100000000 --private-key "$DEP"

say "2. USDC 市场：supply / ETH 抵押 / borrow / repay / withdraw（A）"
send $USDC "faucet(uint256)" 30000000000 --private-key "$keyA"
send $USDC "approve(address,uint256)" $POOL $MAX --private-key "$keyA"
send $POOL "supply(uint8,uint256)" 0 20000000000 --private-key "$keyA"
send $POOL "supplyCollateral()" --value 4000000000000000000 --private-key "$keyA"   # 4 ETH = 12000 USD
send $POOL "borrow(uint8,uint256,uint256)" 0 3000000000 3 --private-key "$keyA"
echo "  USDC debt = $(call $POOL "userDebtToken(address,uint8)(uint256)" $A 0)"
send $POOL "repay(uint8,uint256)" 0 1000000000 --private-key "$keyA"
send $POOL "repay(uint8,uint256)" 0 $MAX --private-key "$keyA"
SH0=$(call $POOL "userSharesOf(address,uint8)(uint256)" $A 0)
send $POOL "withdraw(uint8,uint256)" 0 $((SH0 / 2)) --private-key "$keyA"
echo "  USDC market ok"

say "3. USDT 市场：supply / borrow / repay"
send $USDT "faucet(uint256)" 30000000000 --private-key "$keyA"
send $USDT "approve(address,uint256)" $POOL $MAX --private-key "$keyA"
send $POOL "supply(uint8,uint256)" 1 10000000000 --private-key "$keyA"
send $POOL "borrow(uint8,uint256,uint256)" 1 1500000000 2 --private-key "$keyA"
echo "  USDT debt = $(call $POOL "userDebtToken(address,uint8)(uint256)" $A 1)"
send $USDT "approve(address,uint256)" $POOL $MAX --private-key "$keyA"
send $POOL "repay(uint8,uint256)" 1 $MAX --private-key "$keyA"
echo "  USDT market ok"

say "4. DAI 市场（18 位）：supply / borrow / repay"
send $DAI "faucet(uint256)" 30000000000000000000 --private-key "$keyA"
send $DAI "approve(address,uint256)" $POOL $MAX --private-key "$keyA"
send $POOL "supply(uint8,uint256)" 2 10000000000000000000 --private-key "$keyA"
send $POOL "borrow(uint8,uint256,uint256)" 2 1200000000000000000 1 --private-key "$keyA"
echo "  DAI debt = $(call $POOL "userDebtToken(address,uint8)(uint256)" $A 2)"
send $DAI "approve(address,uint256)" $POOL $MAX --private-key "$keyA"
send $POOL "repay(uint8,uint256)" 2 $MAX --private-key "$keyA"
echo "  DAI market ok"

say "5. wstETH 抵押 → USDC 借款 → 崩盘 → 清算（L 收 wstETH）"
send $WSTETH "faucet(uint256)" 1000000000000000000 --private-key "$keyA"
send $WSTETH "approve(address,uint256)" $POOL $MAX --private-key "$keyA"
send $POOL "supplyCollateral(address,uint256)" $WSTETH 300000000000000000 --private-key "$keyA"  # 0.3 wstETH = 900 USD
send $POOL "borrow(uint8,uint256,uint256)" 0 400000000 5 --private-key "$keyA"
send $SWITCH "setPrice(address,uint256)" $WSTETH 60000000000 --private-key "$DEP"   # wstETH 600 USD
echo "  liquidatable=$(call $POOL "isLiquidatable(address)(bool)" $A)"
send $USDC "faucet(uint256)" 10000000000 --private-key "$keyL"
send $USDC "approve(address,uint256)" $POOL $MAX --private-key "$keyL"
send $POOL "liquidate(address,uint8,address,uint256,uint256)" $A 0 $WSTETH 300000000 0 --private-key "$keyL"
echo "  wstETH collateral remaining = $(call $POOL "userCollateralOf(address,uint256)(uint256)" $A 1)"
echo "  liquidator wstETH = $(call $WSTETH "balanceOf(address)(uint256)" $L)"
send $SWITCH "setPrice(address,uint256)" $WSTETH 300000000000 --private-key "$DEP"

say "6. WBTC 抵押 → USDT 借款（跨资产组合）+ 还款"
send $WBTC "faucet(uint256)" 1000000000 --private-key "$keyA"
send $WBTC "approve(address,uint256)" $POOL $MAX --private-key "$keyA"
send $POOL "supplyCollateral(address,uint256)" $WBTC 200000000 --private-key "$keyA"   # 2 WBTC = 200_000 USD
send $POOL "borrow(uint8,uint256,uint256)" 1 2000000000 5 --private-key "$keyA"       # 2000 USDT
echo "  USDT debt (WBTC-backed) = $(call $POOL "userDebtToken(address,uint8)(uint256)" $A 1)"
send $USDT "faucet(uint256)" 30000000000 --private-key "$keyA"
send $USDT "approve(address,uint256)" $POOL $MAX --private-key "$keyA"
send $POOL "repay(uint8,uint256)" 1 $MAX --private-key "$keyA"

say "7. 汇总"
echo "  HF = $(call $POOL "getUserHealthFactor(address)(uint256)" $A)"
echo "  pos(debt/coll/hf/liq) = $(cast call $POOL "getUserPositionV2(address)(uint256,uint256,uint256,bool)" $A --rpc-url "$RPC" 2>/dev/null | python -c "import sys;d=sys.stdin.read().split();print(' '.join(d[:4]))")"
say "E2E V2 done."
