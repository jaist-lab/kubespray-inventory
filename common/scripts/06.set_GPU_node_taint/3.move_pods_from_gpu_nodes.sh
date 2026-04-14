#!/bin/bash
# 4.move_pods_from_gpu_nodes.sh
# 既存Pod移動スクリプト（環境別対応・DaemonSet除外版）

set -e

echo "📦 Step 3: 既存Pod移動（改訂版）"
echo "================================"

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =======================================================
# 📌 環境選択
# =======================================================
echo "既存Podを移動する環境を選択してください:"
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
echo "${ENV_NAME}環境 既存Pod移動"
echo "対象GPUノード: ${GPU_NODES[@]}"
echo "=========================================="
echo ""

# GPUノード上の既存Pod確認
echo -e "${BLUE}=== GPUノード上の既存Pod確認 ===${NC}"

# 環境に応じたGPUノードのPodを取得
GPU_PODS=""
for node in "${GPU_NODES[@]}"; do
    NODE_PODS=$(kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=$node 2>/dev/null || echo "")
    if [ -n "$NODE_PODS" ]; then
        GPU_PODS="${GPU_PODS}${NODE_PODS}"$'\n'
    fi
done

# 空行削除
GPU_PODS=$(echo "$GPU_PODS" | grep -v "^$")

if [ -z "$GPU_PODS" ]; then
    echo "移動対象のPodはありません"
    echo -e "${GREEN}✅ ${ENV_NAME}環境 Step 3: スキップ${NC}"
    exit 0
fi

echo "$GPU_PODS"
echo ""

# 除外パターン（GPU Operator + DaemonSet管理のシステムPod）
EXCLUDE_PATTERN='nvidia-device-plugin|nvidia-dcgm|nvidia-container-toolkit|nvidia-operator-validator|nvidia-cuda-validator|gpu-feature-discovery|gpu-operator|calico-node|kube-proxy|nodelocaldns|nginx-proxy'

echo -e "${BLUE}=== 移動対象Pod抽出 ===${NC}"
echo "除外対象:"
echo "  - GPU Operator関連Pod"
echo "  - NVIDIA関連システムPod"
echo "  - DaemonSet管理のシステムPod（calico-node, kube-proxy, nodelocaldns, nginx-proxy）"
echo ""

TARGET_PODS=$(echo "$GPU_PODS" | grep -v "NAMESPACE" | grep -vE "$EXCLUDE_PATTERN" || echo "")

if [ -z "$TARGET_PODS" ]; then
    echo "移動対象のPodはありません（システムPodとGPU Operatorのみ）"
    echo ""
    echo -e "${BLUE}=== 残存Pod（正常） ===${NC}"
    echo "$GPU_PODS" | awk 'NR==1 || NR>1 {print $1, $2, $4, $8}' | column -t
    echo ""
    echo -e "${GREEN}✅ ${ENV_NAME}環境 Step 3: 移動不要${NC}"
    exit 0
fi

echo "移動対象:"
echo "$TARGET_PODS" | awk '{print $1, $2, $4, $8}' | column -t
TARGET_COUNT=$(echo "$TARGET_PODS" | wc -l)
echo ""
echo "移動対象数: ${TARGET_COUNT} Pods"
echo ""

read -p "これらのPodを移動しますか？ (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "キャンセルしました"
    exit 0
fi

# 移動処理
echo ""
echo -e "${BLUE}=== Pod移動処理開始 ===${NC}"
MOVE_COUNT=0
SKIP_COUNT=0

while IFS= read -r line; do
    NAMESPACE=$(echo "$line" | awk '{print $1}')
    POD_NAME=$(echo "$line" | awk '{print $2}')
    
    echo ""
    echo -e "${YELLOW}処理中: $NAMESPACE/$POD_NAME${NC}"
    
    # Podの存在確認
    if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "  ${RED}→ Pod not found (スキップ)${NC}"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi
    
    # Deployment/ReplicaSet管理かチェック
    OWNER=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "")
    OWNER_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
    
    echo "  Owner: ${OWNER:-None} ${OWNER_NAME:+($OWNER_NAME)}"
    
    if [ "$OWNER" = "ReplicaSet" ]; then
        # Deploymentを取得
        DEPLOY_NAME=$(kubectl get rs "$OWNER_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
        
        if [ -n "$DEPLOY_NAME" ]; then
            echo -e "  ${GREEN}→ Deployment: $DEPLOY_NAME をrolling restart${NC}"
            kubectl rollout restart deployment "$DEPLOY_NAME" -n "$NAMESPACE"
            MOVE_COUNT=$((MOVE_COUNT + 1))
        else
            echo -e "  ${GREEN}→ Pod削除（自動再作成）${NC}"
            kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --grace-period=30
            MOVE_COUNT=$((MOVE_COUNT + 1))
        fi
    elif [ "$OWNER" = "DaemonSet" ]; then
        echo -e "  ${YELLOW}→ DaemonSet管理（スキップ）${NC}"
        SKIP_COUNT=$((SKIP_COUNT + 1))
    elif [ "$OWNER" = "StatefulSet" ]; then
        echo -e "  ${GREEN}→ StatefulSet: $OWNER_NAME を再起動${NC}"
        kubectl rollout restart statefulset "$OWNER_NAME" -n "$NAMESPACE"
        MOVE_COUNT=$((MOVE_COUNT + 1))
    elif [ "$OWNER" = "Job" ]; then
        echo -e "  ${YELLOW}→ Job管理（手動確認推奨）${NC}"
        SKIP_COUNT=$((SKIP_COUNT + 1))
    else
        echo -e "  ${GREEN}→ Pod削除（自動再作成）${NC}"
        kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --grace-period=30
        MOVE_COUNT=$((MOVE_COUNT + 1))
    fi
    
done <<< "$TARGET_PODS"

if [ $MOVE_COUNT -gt 0 ]; then
    echo ""
    echo -e "${BLUE}=== 移動完了待機（60秒） ===${NC}"
    echo "Podが他のノードに再スケジュールされるのを待っています..."
    sleep 60
fi

echo ""
echo -e "${GREEN}✅ ${ENV_NAME}環境 Step 3: 既存Pod移動完了${NC}"
echo "=========================================="
echo "処理結果:"
echo "  - 移動処理数: ${MOVE_COUNT}"
echo "  - スキップ数: ${SKIP_COUNT}"
echo "=========================================="

# 結果確認
echo ""
echo -e "${BLUE}=== 移動後のGPUノード上Pod ===${NC}"
REMAINING_PODS=""
for node in "${GPU_NODES[@]}"; do
    echo ""
    echo -e "${YELLOW}--- $node ---${NC}"
    NODE_PODS=$(kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=$node 2>/dev/null)
    if [ -n "$NODE_PODS" ]; then
        echo "$NODE_PODS" | awk 'NR==1 || NR>1 {print $1, $2, $4, $8}' | column -t
        REMAINING_COUNT=$(echo "$NODE_PODS" | grep -v "NAMESPACE" | wc -l)
        echo ""
        echo "残存Pod数: ${REMAINING_COUNT}"
        REMAINING_PODS="${REMAINING_PODS}${NODE_PODS}"$'\n'
    else
        echo "Podなし"
    fi
done

# GPU Operator Podのみか確認
echo ""
echo -e "${BLUE}=== 検証 ===${NC}"
NON_SYSTEM_PODS=$(echo "$REMAINING_PODS" | grep -v "NAMESPACE" | grep -vE "$EXCLUDE_PATTERN" || echo "")
if [ -z "$NON_SYSTEM_PODS" ]; then
    echo -e "${GREEN}✅ GPUノード上にはGPU OperatorとシステムPodのみ存在（正常）${NC}"
else
    echo -e "${YELLOW}⚠️  以下の非システムPodが残っています:${NC}"
    echo "$NON_SYSTEM_PODS" | awk '{print $1, $2, $8}' | column -t
    echo ""
    echo "これらのPodは手動で確認してください"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "✅ ${ENV_NAME}環境 既存Pod移動処理完了"
echo "==========================================${NC}"