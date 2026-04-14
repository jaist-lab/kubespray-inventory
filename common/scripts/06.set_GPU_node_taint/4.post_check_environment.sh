#!/bin/bash
# 5.post_check_environment.sh
# Taint設定後確認スクリプト（環境別対応版）

set -e

echo "=============================="
echo "🔍 GPUノード状態確認"
echo "=============================="

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =======================================================
# 📌 環境選択
# =======================================================
echo "確認する環境を選択してください:"
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
        echo -e "${YELLOW}Development環境にはGPUノードが存在しません（rtxsv1は除外済み）${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}無効な選択肢です。1または2を選択してください。${NC}"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "${ENV_NAME}環境 GPUノード状態確認"
echo "対象GPUノード: ${GPU_NODES[@]}"
echo "=========================================="
echo ""

# GPUノード上のPod一覧取得
echo -e "${BLUE}=== GPUノード上のPod一覧 ===${NC}"

GPU_PODS=""
for node in "${GPU_NODES[@]}"; do
    NODE_PODS=$(kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=$node 2>/dev/null || true)
    if [ -n "$NODE_PODS" ]; then
        GPU_PODS="${GPU_PODS}${NODE_PODS}"$'\n'
    fi
done

# 空行とヘッダー行を除去
GPU_PODS=$(echo "$GPU_PODS" | grep -v "^$" | grep -v "^NAMESPACE")

if [ -z "$GPU_PODS" ]; then
    echo "GPUノード上にPodはありません"
    echo -e "${GREEN}✅ ${ENV_NAME}環境 GPU専用化完了（100%）${NC}"
    exit 0
fi

# Pod一覧表示
echo "$GPU_PODS" | awk '{print $1, $2, $4, $8}' | column -t
TOTAL_PODS=$(echo "$GPU_PODS" | wc -l)
echo ""
echo "総Pod数: ${TOTAL_PODS}"
echo ""

# カテゴリ別集計
echo -e "${BLUE}=== Pod分類 ===${NC}"

# DaemonSet（システム必須）
DAEMONSET_PODS=$(echo "$GPU_PODS" | grep -E 'calico-node|kube-proxy|nodelocaldns|nginx-proxy' || true)
if [ -n "$DAEMONSET_PODS" ]; then
    DAEMONSET_COUNT=$(echo "$DAEMONSET_PODS" | wc -l)
else
    DAEMONSET_COUNT=0
fi

# GPU Operator関連（すべて含む）
GPU_OP_PODS=$(echo "$GPU_PODS" | grep -E 'nvidia-device-plugin|nvidia-dcgm|nvidia-container-toolkit|nvidia-operator-validator|nvidia-cuda-validator|gpu-feature-discovery|gpu-operator' || true)
if [ -n "$GPU_OP_PODS" ]; then
    GPU_OP_COUNT=$(echo "$GPU_OP_PODS" | wc -l)
else
    GPU_OP_COUNT=0
fi

# 移動可能なPod（システムとGPU Operator以外）
MOVABLE_PODS=$(echo "$GPU_PODS" | grep -vE 'calico-node|kube-proxy|nodelocaldns|nginx-proxy|nvidia-device-plugin|nvidia-dcgm|nvidia-container-toolkit|nvidia-operator-validator|nvidia-cuda-validator|gpu-feature-discovery|gpu-operator' || true)
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
echo -e "${BLUE}=== 専用化評価 ===${NC}"

if [ ${MOVABLE_COUNT} -eq 0 ]; then
    echo -e "${GREEN}✅ ${ENV_NAME}環境 GPU専用化完了（100%）${NC}"
    echo "残存Podはすべてシステム必須コンポーネントです"

    echo ""
    echo "=== システム必須Pod内訳 ==="
    if [ ${DAEMONSET_COUNT} -gt 0 ]; then
        echo "DaemonSet:"
        echo "$DAEMONSET_PODS" | awk '{print "  " $1 "/" $2 " on " $8}'
    fi

    if [ ${GPU_OP_COUNT} -gt 0 ]; then
        echo ""
        echo "GPU Operator:"
        echo "$GPU_OP_PODS" | awk '{print "  " $1 "/" $2 " on " $8}'
    fi

elif [ ${MOVABLE_COUNT} -le 2 ]; then
    echo -e "${GREEN}✅ ${ENV_NAME}環境 GPU専用化良好（95%）${NC}"
    echo ""
    echo "残存移動可能Pod（${MOVABLE_COUNT}個）:"
    echo "$MOVABLE_PODS" | awk '{print "  " $1 "/" $2 " on " $8}'

elif [ ${MOVABLE_COUNT} -le 5 ]; then
    echo -e "${YELLOW}⚠️  ${ENV_NAME}環境 GPU専用化要改善（80%）${NC}"
    echo ""
    echo "残存移動可能Pod（${MOVABLE_COUNT}個）:"
    echo "$MOVABLE_PODS" | awk '{print "  " $1 "/" $2 " on " $8}'

else
    echo -e "${RED}❌ ${ENV_NAME}環境 GPU専用化不十分${NC}"
    echo ""
    echo "残存移動可能Pod（${MOVABLE_COUNT}個）:"
    echo "$MOVABLE_PODS" | awk '{print "  " $1 "/" $2 " on " $8}'
    echo ""
    echo "対処方法:"
    echo "  ./4.move_pods_from_gpu_nodes.sh を再実行してください"
fi

# 詳細情報
echo ""
echo -e "${BLUE}=== 詳細情報 ===${NC}"
echo "ノード別Pod配置:"

for node in "${GPU_NODES[@]}"; do
    NODE_POD_COUNT=$(echo "$GPU_PODS" | grep -c "$node" || echo 0)
    echo "  ${node}: ${NODE_POD_COUNT} Pods"
    
    # ノードごとのPodタイプ内訳
    NODE_DAEMONSET=$(echo "$GPU_PODS" | grep "$node" | grep -cE 'calico-node|kube-proxy|nodelocaldns|nginx-proxy' || echo 0)
    NODE_GPU_OP=$(echo "$GPU_PODS" | grep "$node" | grep -cE 'nvidia-device-plugin|nvidia-dcgm|nvidia-container-toolkit|nvidia-operator-validator|nvidia-cuda-validator|gpu-feature-discovery|gpu-operator' || echo 0)
    NODE_MOVABLE=$(echo "$GPU_PODS" | grep "$node" | grep -vcE 'calico-node|kube-proxy|nodelocaldns|nginx-proxy|nvidia-device-plugin|nvidia-dcgm|nvidia-container-toolkit|nvidia-operator-validator|nvidia-cuda-validator|gpu-feature-discovery|gpu-operator' || echo 0)
    
    echo "    - DaemonSet: ${NODE_DAEMONSET}"
    echo "    - GPU Operator: ${NODE_GPU_OP}"
    echo "    - 移動可能: ${NODE_MOVABLE}"
done

# GPU検出状態確認
echo ""
echo -e "${BLUE}=== GPU検出状態 ===${NC}"
for node in "${GPU_NODES[@]}"; do
    GPU_CAPACITY=$(kubectl get node $node -o jsonpath='{.status.capacity.nvidia\.com/gpu}' 2>/dev/null || echo "0")
    GPU_ALLOCATABLE=$(kubectl get node $node -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
    
    if [ "$GPU_CAPACITY" != "0" ]; then
        echo -e "  ${GREEN}${node}: ${GPU_CAPACITY} GPU (Allocatable: ${GPU_ALLOCATABLE})${NC}"
    else
        echo -e "  ${YELLOW}${node}: GPU未検出${NC}"
    fi
done

# Taint確認
echo ""
echo -e "${BLUE}=== Taint状態 ===${NC}"
for node in "${GPU_NODES[@]}"; do
    echo "${node}:"
    TAINTS=$(kubectl get node $node -o jsonpath='{.spec.taints}' 2>/dev/null)
    if [ -n "$TAINTS" ] && [ "$TAINTS" != "null" ]; then
        echo "$TAINTS" | jq -r '.[] | "  - \(.key)=\(.value):\(.effect)"' 2>/dev/null || echo "  $TAINTS"
    else
        echo "  なし"
    fi
done

# GPU Operator Pod状態
echo ""
echo -e "${BLUE}=== GPU Operator Pod状態 ===${NC}"
if [ ${GPU_OP_COUNT} -gt 0 ]; then
    echo "$GPU_OP_PODS" | awk '{print $1, $2, $4, $8}' | column -t
else
    echo "GPU Operator Podなし"
fi

# サマリー
echo ""
echo "=========================================="
echo -e "${BLUE}📊 ${ENV_NAME}環境 確認サマリー${NC}"
echo "=========================================="
echo "総Pod数: ${TOTAL_PODS}"
echo "  - システム必須: ${DAEMONSET_COUNT}"
echo "  - GPU Operator: ${GPU_OP_COUNT}"
echo "  - 移動可能: ${MOVABLE_COUNT}"
echo ""

# 専用化率計算
if [ ${TOTAL_PODS} -gt 0 ]; then
    REQUIRED_PODS=$((DAEMONSET_COUNT + GPU_OP_COUNT))
    SPECIALIZATION_RATE=$((REQUIRED_PODS * 100 / TOTAL_PODS))
    echo "GPU専用化率: ${SPECIALIZATION_RATE}%"
else
    echo "GPU専用化率: 100%"
fi

echo "=========================================="

# 最終判定
echo ""
if [ ${MOVABLE_COUNT} -eq 0 ]; then
    echo -e "${GREEN}🎉 ${ENV_NAME}環境はGPU専用ノードとして最適化されています！${NC}"
    exit 0
elif [ ${MOVABLE_COUNT} -le 2 ]; then
    echo -e "${GREEN}✅ ${ENV_NAME}環境のGPU専用化はほぼ完了しています${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  ${ENV_NAME}環境には改善の余地があります${NC}"
    exit 1
fi