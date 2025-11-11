#!/bin/bash
# 4.post_check_environment.sh
# Taint設定後確認スクリプト


# GPUノード状態確認スクリプト

set -e

echo "=============================="
echo "🔍 GPUノード状態確認"
echo "=============================="

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=== GPUノード上のPod一覧 ==="
GPU_PODS=$(kubectl get pods --all-namespaces -o wide | grep -E 'dlcsv1|dlcsv2' || true)

if [ -z "$GPU_PODS" ]; then
    echo "GPUノード上にPodはありません"
    echo -e "${GREEN}✅ GPU専用化完了（100%）${NC}"
    exit 0
fi

echo "$GPU_PODS"
echo ""

# カテゴリ別集計（修正版）
echo "=== Pod分類 ==="

# DaemonSet（システム必須）
DAEMONSET_PODS=$(echo "$GPU_PODS" | grep -E 'calico-node|kube-proxy|nodelocaldns|nginx-proxy' || true)
if [ -n "$DAEMONSET_PODS" ]; then
    DAEMONSET_COUNT=$(echo "$DAEMONSET_PODS" | wc -l)
else
    DAEMONSET_COUNT=0
fi

# GPU Operator
GPU_OP_PODS=$(echo "$GPU_PODS" | grep -E 'nvidia-device-plugin|nvidia-dcgm|gpu-operator' || true)
if [ -n "$GPU_OP_PODS" ]; then
    GPU_OP_COUNT=$(echo "$GPU_OP_PODS" | wc -l)
else
    GPU_OP_COUNT=0
fi

# 移動可能なPod
MOVABLE_PODS=$(echo "$GPU_PODS" | grep -vE 'calico-node|kube-proxy|nodelocaldns|nginx-proxy|nvidia-device-plugin|nvidia-dcgm|gpu-operator' || true)
if [ -n "$MOVABLE_PODS" ]; then
    MOVABLE_COUNT=$(echo "$MOVABLE_PODS" | wc -l)
else
    MOVABLE_COUNT=0
fi

echo "DaemonSet（システム必須）: ${DAEMONSET_COUNT}"
echo "GPU Operator（GPU必須）:   ${GPU_OP_COUNT}"
echo "移動可能なPod:             ${MOVABLE_COUNT}"
echo ""

# 評価
if [ ${MOVABLE_COUNT} -eq 0 ]; then
    echo -e "${GREEN}✅ GPU専用化完了（100%）${NC}"
    echo "残存Podはすべてシステム必須コンポーネントです"

    echo ""
    echo "=== システム必須Pod内訳 ==="
    echo "DaemonSet:"
    echo "$DAEMONSET_PODS" | awk '{print "  " $1 "/" $2 " on " $8}'

    if [ ${GPU_OP_COUNT} -gt 0 ]; then
        echo ""
        echo "GPU Operator:"
        echo "$GPU_OP_PODS" | awk '{print "  " $1 "/" $2 " on " $8}'
    fi

elif [ ${MOVABLE_COUNT} -le 2 ]; then
    echo -e "${GREEN}✅ GPU専用化良好（95%）${NC}"
    echo ""
    echo "残存移動可能Pod（${MOVABLE_COUNT}個）:"
    echo "$MOVABLE_PODS" | awk '{print "  " $1 "/" $2 " on " $8}'

elif [ ${MOVABLE_COUNT} -le 5 ]; then
    echo -e "${YELLOW}⚠️ GPU専用化要改善（80%）${NC}"
    echo ""
    echo "残存移動可能Pod（${MOVABLE_COUNT}個）:"
    echo "$MOVABLE_PODS" | awk '{print "  " $1 "/" $2 " on " $8}'

else
    echo -e "${RED}❌ GPU専用化不十分${NC}"
    echo ""
    echo "残存移動可能Pod（${MOVABLE_COUNT}個）:"
    echo "$MOVABLE_PODS" | awk '{print "  " $1 "/" $2 " on " $8}'
    echo ""
    echo "対処方法:"
    echo "  ./step3_move_pods_from_gpu_nodes_fixed.sh を再実行してください"
fi

echo ""
echo "=== 詳細情報 ==="
echo "ノード別Pod配置:"
DLCSV1_COUNT=$(echo "$GPU_PODS" | grep -c dlcsv1 || echo 0)
DLCSV2_COUNT=$(echo "$GPU_PODS" | grep -c dlcsv2 || echo 0)
echo "  dlcsv1: ${DLCSV1_COUNT} Pods"
echo "  dlcsv2: ${DLCSV2_COUNT} Pods"
