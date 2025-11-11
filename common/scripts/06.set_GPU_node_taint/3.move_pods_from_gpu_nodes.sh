#!/bin/bash
# 3.move_pods_from_gpu_nodes.sh
# 既存Pod移動スクリプト（DaemonSet除外版）

set -e

echo "📦 Step 3: 既存Pod移動（改訂版）"
echo "================================"

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=== GPUノード上の既存Pod確認 ==="
GPU_PODS=$(kubectl get pods --all-namespaces -o wide | grep -E 'dlcsv1|dlcsv2' || echo "")

if [ -z "$GPU_PODS" ]; then
    echo "移動対象のPodはありません"
    echo -e "${GREEN}✅ Step 3: スキップ${NC}"
    exit 0
fi

echo "$GPU_PODS"
echo ""

# 除外パターン（GPU Operator + DaemonSet管理のシステムPod）
EXCLUDE_PATTERN='nvidia-device-plugin|nvidia-dcgm|gpu-operator|calico-node|kube-proxy|nodelocaldns|nginx-proxy'

echo "=== 移動対象Pod抽出 ==="
echo "除外対象:"
echo "  - GPU Operator関連Pod"
echo "  - DaemonSet管理のシステムPod（calico-node, kube-proxy, nodelocaldns, nginx-proxy）"
echo ""

TARGET_PODS=$(echo "$GPU_PODS" | grep -vE "$EXCLUDE_PATTERN" || echo "")

if [ -z "$TARGET_PODS" ]; then
    echo "移動対象のPodはありません（システムPodとGPU Operatorのみ）"
    echo ""
    echo "=== 残存Pod（正常） ==="
    echo "$GPU_PODS" | awk '{print $1, $2, $8}' | column -t
    echo ""
    echo -e "${GREEN}✅ Step 3: 移動不要${NC}"
    exit 0
fi

echo "移動対象:"
echo "$TARGET_PODS" | awk '{print $1, $2, $8}' | column -t
echo ""

read -p "これらのPodを移動しますか？ (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "キャンセルしました"
    exit 0
fi

# 移動処理
echo ""
echo "=== Pod移動処理開始 ==="
MOVE_COUNT=0

while IFS= read -r line; do
    NAMESPACE=$(echo "$line" | awk '{print $1}')
    POD_NAME=$(echo "$line" | awk '{print $2}')
    
    echo ""
    echo "処理中: $NAMESPACE/$POD_NAME"
    
    # Deployment/ReplicaSet管理かチェック
    OWNER=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "")
    OWNER_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
    
    echo "  Owner: $OWNER ($OWNER_NAME)"
    
    if [ "$OWNER" = "ReplicaSet" ]; then
        # Deploymentを取得
        DEPLOY_NAME=$(kubectl get rs "$OWNER_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
        
        if [ -n "$DEPLOY_NAME" ]; then
            echo "  → Deployment: $DEPLOY_NAME をrolling restart"
            kubectl rollout restart deployment "$DEPLOY_NAME" -n "$NAMESPACE"
            MOVE_COUNT=$((MOVE_COUNT + 1))
        else
            echo "  → Pod削除（自動再作成）"
            kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --grace-period=30
            MOVE_COUNT=$((MOVE_COUNT + 1))
        fi
    elif [ "$OWNER" = "DaemonSet" ]; then
        echo -e "  → ${YELLOW}DaemonSet管理（スキップ）${NC}"
    elif [ "$OWNER" = "StatefulSet" ]; then
        echo "  → StatefulSet: $OWNER_NAME を再起動"
        kubectl rollout restart statefulset "$OWNER_NAME" -n "$NAMESPACE"
        MOVE_COUNT=$((MOVE_COUNT + 1))
    else
        echo "  → Pod削除（自動再作成）"
        kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --grace-period=30
        MOVE_COUNT=$((MOVE_COUNT + 1))
    fi
    
done <<< "$TARGET_PODS"

if [ $MOVE_COUNT -gt 0 ]; then
    echo ""
    echo "=== 移動完了待機（60秒） ==="
    sleep 60
fi

echo ""
echo -e "${GREEN}✅ Step 3: 既存Pod移動完了${NC}"
echo "移動処理数: ${MOVE_COUNT}"

# 結果確認
echo ""
echo "=== 移動後のGPUノード上Pod ==="
kubectl get pods --all-namespaces -o wide | grep -E 'dlcsv1|dlcsv2' | awk '{print $1, $2, $8}' | column -t
