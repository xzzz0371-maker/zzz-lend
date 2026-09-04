# ============================================================
#  ZZZ Lend — 部署 Safe 2/3 多签（Base · chainId 8453）
#  用法（PowerShell，先改下方 O1/O2/O3 与 DEPLOYER_KEY）:
#    .\deploy-safe.ps1
#  ⚠️ 只做"预览地址"（getAddressForCounterfactualSafe）时不花 gas；
#     确认地址后再广播 createProxyWithNonce（需部署者钱包有 Base ETH）。
# ============================================================

# --- 三个 owner 地址（必填：你与另外两位可信签名者）---
$O1 = "0x0000000000000000000000000000000000000000"
$O2 = "0x0000000000000000000000000000000000000000"
$O3 = "0x0000000000000000000000000000000000000000"

# --- 阈值（2/3）---
$Threshold = "2"

# --- 部署者私钥（支付 gas；可用主网部署者同款或单独钱包）---
$DEPLOYER_KEY = "0x0000000000000000000000000000000000000000000000000000000000000000"

# --- Base 官方 Safe v1.4.1（已链上核验）---
$FACTORY    = "0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67"
$SINGLETON  = "0x41675C099F32341bf84BFc5382aF534df5C7461a"
$HANDLER    = "0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99"
$ZERO       = "0x0000000000000000000000000000000000000000"
$RPC        = "https://mainnet.base.org"
$NONCE      = "1"

# --- setupData: setup(owners, threshold, to=0, data=0x, fallbackHandler, paymentToken=0, payment=0, paymentReceiver=0) ---
$SETUP = & cast calldata "setup(address[],uint256,address,bytes,address,address,uint256,address)" "[$O1,$O2,$O3]" $Threshold $ZERO "0x" $HANDLER $ZERO "0" $ZERO

Write-Host "===== setupData =====" -ForegroundColor Cyan
Write-Host $SETUP

Write-Host "`n===== 预览 Safe 地址（不花 gas）=====" -ForegroundColor Cyan
$PREVIEW = & cast call $FACTORY "getAddressForCounterfactualSafe(address,bytes,uint256)(address)" $SINGLETON $SETUP $NONCE --rpc-url $RPC
Write-Host "Safe 地址(预览): $PREVIEW"
Write-Host "`n⚠️  请人工确认该地址与 Safe{Wallet} 界面预期一致后再广播。"

Write-Host "`n===== 广播创建（花 gas）=====" -ForegroundColor Yellow
Write-Host "执行以下命令创建（确认地址无误后）:"
Write-Host "  cast send $FACTORY 'createProxyWithNonce(address,bytes,uint256)' $SINGLETON $SETUP $NONCE --rpc-url $RPC --private-key $DEPLOYER_KEY --chain 8453"
