#!/bin/bash
# 3.setup_taint_gpu_node.sh
# GPU Taint設定スクリプト

set -e

echo "🔧 Step 2: GPU Taint設定"
echo "========================"

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=== Taint設定実行 ==="
echo "対象ノード: dlcsv1, dlcsv2"
echo "Taint: dedicated=gpu-compute:NoSchedule"
echo ""

# dlcsv1にTaint設定
echo "dlcsv1にTaint設定中..."
if kubectl taint node dlcsv1 dedicated=gpu-compute:NoSchedule --overwrite; then
    echo -e "${GREEN}✅ dlcsv1: Taint設定成功${NC}"
else
    echo -e "${RED}❌ dlcsv1: Taint設定失敗${NC}"
    exit 1
fi

# dlcsv2にTaint設定
echo ""
echo "dlcsv2にTaint設定中..."
if kubectl taint node dlcsv2 dedicated=gpu-compute:NoSchedule --overwrite; then
    echo -e "${GREEN}✅ dlcsv2: Taint設定成功${NC}"
else
    echo -e "${RED}❌ dlcsv2: Taint設定失敗${NC}"
    exit 1
fi

echo ""
echo "=== Taint設定確認 ==="
echo ""
echo "--- dlcsv1 ---"
kubectl describe node dlcsv1 | grep -A 5 "Taints:"

echo ""
echo "--- dlcsv2 ---"
kubectl describe node dlcsv2 | grep -A 5 "Taints:"

echo ""
echo -e "${GREEN}✅ Step 2: GPU Taint設定完了${NC}"
echo ""
echo "効果: 新規Podは自動的にGPUノード以外に配置されます"
echo "次のステップで既存Podを移動します"
