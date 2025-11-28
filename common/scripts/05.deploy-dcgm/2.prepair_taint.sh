#!/bin/bash
# 手動設定削除スクリプト（環境別対応版）

echo "🧹 手動設定削除（完全自動検出準備）"
echo "================================="

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 環境選択
echo "手動設定を削除する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo ""
read -p "選択 (1/2): " ENV_CHOICE

# 環境別の設定
case $ENV_CHOICE in
    1)
        echo -e "${GREEN}Production環境を選択${NC}"
        export KUBECONFIG=~/.kube/config-production
        GPU_NODES=("dlcsv1" "dlcsv2")
        ENV_NAME="Production"
        ;;
    2)
        echo -e "${GREEN}Development環境を選択${NC}"
        export KUBECONFIG=~/.kube/config-development
        GPU_NODES=("rtxsv1")
        ENV_NAME="Development"
        ;;
    *)
        echo -e "${RED}無効な選択肢です。1または2を選択してください。${NC}"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "${ENV_NAME}環境の手動設定削除"
echo "対象ノード: ${GPU_NODES[@]}"
echo "=========================================="
echo ""

# 手動Taint削除
echo "=== 手動Taint削除 ==="
for node in "${GPU_NODES[@]}"; do
    if kubectl taint node $node dedicated=gpu-compute:NoSchedule- 2>/dev/null; then
        echo -e "${GREEN}✅ ${node}のTaint削除完了${NC}"
    else
        echo -e "${YELLOW}ℹ️  ${node}にTaintなし${NC}"
    fi
done

echo ""
echo "=== 手動ラベル削除 ==="
# 既存の手動ラベルを削除
for node in "${GPU_NODES[@]}"; do
    if kubectl label node $node workload-type- 2>/dev/null; then
        echo -e "${GREEN}✅ ${node}のラベル削除完了${NC}"
    else
        echo -e "${YELLOW}ℹ️  ${node}にラベルなし${NC}"
    fi
done

echo ""
echo "=== 削除後確認 ==="
echo "Taint状況:"
kubectl get nodes ${GPU_NODES[@]} -o custom-columns="NAME:.metadata.name,TAINTS:.spec.taints[*].key" 2>/dev/null || echo "ノード情報取得エラー"

echo ""
echo "ラベル状況:"
kubectl get nodes ${GPU_NODES[@]} --show-labels 2>/dev/null | grep -E "(workload-type|dedicated)" || echo -e "${GREEN}手動ラベルなし${NC}"

echo ""
echo -e "${GREEN}✅ ${ENV_NAME}環境の手動設定削除完了 - 完全自動検出の準備完了${NC}"