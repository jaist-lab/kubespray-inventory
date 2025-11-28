#!/bin/bash
# 1.check_environment.sh
# 環境確認スクリプト

set -e

echo "🔍 Step 1: 環境確認"
echo "===================="

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=== ノード構成確認 ==="
kubectl get nodes -o wide

echo ""
echo "=== ノード詳細（Taint/Label） ==="
for node in master01 master02 master03 node01 node02 dlcsv1 dlcsv2; do
    if kubectl get node $node >/dev/null 2>&1; then
        echo ""
        echo "--- $node ---"
        echo "Taints:"
        kubectl get node $node -o jsonpath='{.spec.taints}' | jq '.' 2>/dev/null || echo "  なし"
        echo "Labels (抜粋):"
        kubectl get node $node --show-labels | grep -oP 'node-role[^,]*|nvidia[^,]*|argocd[^,]*' || echo "  特記事項なし"
    fi
done

echo ""
echo "=== GPUノード(dlcsv1/dlcsv2)上の現在のPod配置 ==="
GPU_PODS=$(kubectl get pods --all-namespaces -o wide | grep -E 'dlcsv1|dlcsv2')
if [ -n "$GPU_PODS" ]; then
    echo "$GPU_PODS" | awk '{print $1, $2, $8}' | column -t
    GPU_POD_COUNT=$(echo "$GPU_PODS" | wc -l)
    echo ""
    echo "合計: ${GPU_POD_COUNT} Pods"
else
    echo "  Podなし"
fi

echo ""
echo "=== GPU Operator Toleration確認 ==="
echo "nvidia-device-plugin-daemonset:"
kubectl get daemonset -n gpu-operator nvidia-device-plugin-daemonset -o jsonpath='{.spec.template.spec.tolerations}' 2>/dev/null | jq '.' || echo "  見つかりません"

echo ""
echo "nvidia-dcgm-exporter:"
kubectl get daemonset -n gpu-operator nvidia-dcgm-exporter -o jsonpath='{.spec.template.spec.tolerations}' 2>/dev/null | jq '.' || echo "  見つかりません"

echo ""
echo "=== ArgoCD インストール確認 ==="
if kubectl get namespace argocd >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  ArgoCD は既にインストールされています${NC}"
    kubectl get pods -n argocd -o wide
else
    echo -e "${GREEN}✅ ArgoCD は未インストールです${NC}"
fi

echo ""
echo -e "${GREEN}✅ Step 1: 環境確認完了${NC}"
