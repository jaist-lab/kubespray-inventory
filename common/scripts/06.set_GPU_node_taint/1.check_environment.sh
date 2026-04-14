#!/bin/bash
# 1.check_environment.sh
# 環境確認スクリプト（環境別対応版）

set -e

echo "🔍 Step 1: 環境確認"
echo "===================="

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
        CONTROL_NODES=("prod-master01" "prod-master02" "prod-master03")
        WORKER_NODES=("prod-node01" "prod-node02")
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
echo "${ENV_NAME}環境 確認"
echo "GPUノード: ${GPU_NODES[@]}"
echo "=========================================="
echo ""

# Kubernetesクラスタ接続確認
echo -e "${BLUE}=== Kubernetesクラスタ接続確認 ===${NC}"
if kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
    echo -e "${GREEN}✅ クラスタ接続成功${NC}"
    kubectl cluster-info | head -2
else
    echo -e "${RED}❌ クラスタ接続失敗${NC}"
    echo "KUBECONFIG: $KUBECONFIG"
    exit 1
fi

echo ""
echo -e "${BLUE}=== ノード構成確認 ===${NC}"
kubectl get nodes -o wide

echo ""
echo -e "${BLUE}=== GPUノード詳細確認 ===${NC}"
for node in "${GPU_NODES[@]}"; do
    if kubectl get node $node >/dev/null 2>&1; then
        echo ""
        echo -e "${YELLOW}--- $node ---${NC}"
        
        # ノード状態
        NODE_STATUS=$(kubectl get node $node -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        echo "状態: $([ "$NODE_STATUS" == "True" ] && echo -e "${GREEN}Ready${NC}" || echo -e "${RED}NotReady${NC}")"
        
        # Taints確認
        echo "Taints:"
        TAINTS=$(kubectl get node $node -o jsonpath='{.spec.taints}' 2>/dev/null)
        if [ -n "$TAINTS" ] && [ "$TAINTS" != "null" ]; then
            echo "$TAINTS" | jq '.' 2>/dev/null || echo "  $TAINTS"
        else
            echo "  なし"
        fi
        
        # Labels確認（GPU関連のみ）
        echo "Labels (GPU関連):"
        kubectl get node $node --show-labels 2>/dev/null | \
            grep -oP 'nvidia[^,]*' | head -10 || echo "  nvidia関連ラベルなし"
        
        # GPU容量確認
        echo "GPU容量:"
        GPU_CAPACITY=$(kubectl get node $node -o jsonpath='{.status.capacity.nvidia\.com/gpu}' 2>/dev/null || echo "0")
        GPU_ALLOCATABLE=$(kubectl get node $node -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
        if [ "$GPU_CAPACITY" != "0" ]; then
            echo -e "  ${GREEN}Capacity: ${GPU_CAPACITY}, Allocatable: ${GPU_ALLOCATABLE}${NC}"
        else
            echo -e "  ${YELLOW}GPU未検出${NC}"
        fi
    else
        echo -e "${RED}❌ ノード $node が見つかりません${NC}"
    fi
done

# 全ノードのTaint/Label概要
echo ""
echo -e "${BLUE}=== 全ノード Taint/Label 概要 ===${NC}"
ALL_NODES=("${CONTROL_NODES[@]}" "${WORKER_NODES[@]}" "${GPU_NODES[@]}")
for node in "${ALL_NODES[@]}"; do
    if kubectl get node $node >/dev/null 2>&1; then
        echo ""
        echo -e "${YELLOW}--- $node ---${NC}"
        
        # Taints
        echo "Taints:"
        TAINTS=$(kubectl get node $node -o jsonpath='{.spec.taints}' 2>/dev/null)
        if [ -n "$TAINTS" ] && [ "$TAINTS" != "null" ]; then
            echo "$TAINTS" | jq -r '.[] | "  - \(.key)=\(.value):\(.effect)"' 2>/dev/null || echo "  $TAINTS"
        else
            echo "  なし"
        fi
        
        # 主要Labels
        echo "Labels (抜粋):"
        kubectl get node $node --show-labels 2>/dev/null | \
            grep -oP 'node-role[^,]*|nvidia[^,]*|argocd[^,]*' | head -5 || echo "  特記事項なし"
    fi
done

echo ""
echo -e "${BLUE}=== GPUノード上の現在のPod配置 ===${NC}"
GPU_PODS=""
for node in "${GPU_NODES[@]}"; do
    NODE_PODS=$(kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=$node 2>/dev/null)
    if [ -n "$NODE_PODS" ]; then
        GPU_PODS="${GPU_PODS}${NODE_PODS}"$'\n'
    fi
done

if [ -n "$GPU_PODS" ]; then
    echo "$GPU_PODS" | grep -v "^$" | awk 'NR==1 || NR>1 {print $1, $2, $4, $7, $8}' | column -t
    GPU_POD_COUNT=$(echo "$GPU_PODS" | grep -v "^$" | grep -v "NAMESPACE" | wc -l)
    echo ""
    echo -e "${GREEN}合計: ${GPU_POD_COUNT} Pods${NC}"
    
    # GPU使用Pod
    echo ""
    echo "GPU使用中のPod:"
    kubectl get pods --all-namespaces -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null) | "\(.metadata.namespace)/\(.metadata.name) (\(.spec.nodeName))"' || \
        echo "  なし"
else
    echo "  Podなし"
fi

echo ""
echo -e "${BLUE}=== GPU Operator 状態確認 ===${NC}"

# GPU Operator ネームスペース確認
if kubectl get namespace gpu-operator >/dev/null 2>&1; then
    echo -e "${GREEN}✅ gpu-operator ネームスペース存在${NC}"
    
    # DaemonSet確認
    echo ""
    echo "DaemonSet一覧:"
    kubectl get daemonsets -n gpu-operator -o wide 2>/dev/null || echo "  DaemonSetなし"
    
    # nvidia-device-plugin Toleration
    echo ""
    echo "nvidia-device-plugin-daemonset Toleration:"
    if kubectl get daemonset -n gpu-operator nvidia-device-plugin-daemonset >/dev/null 2>&1; then
        kubectl get daemonset -n gpu-operator nvidia-device-plugin-daemonset -o jsonpath='{.spec.template.spec.tolerations}' 2>/dev/null | jq '.' || echo "  取得失敗"
    else
        echo "  見つかりません"
    fi
    
    # nvidia-dcgm-exporter Toleration
    echo ""
    echo "nvidia-dcgm-exporter Toleration:"
    if kubectl get daemonset -n gpu-operator nvidia-dcgm-exporter >/dev/null 2>&1; then
        kubectl get daemonset -n gpu-operator nvidia-dcgm-exporter -o jsonpath='{.spec.template.spec.tolerations}' 2>/dev/null | jq '.' || echo "  取得失敗"
    else
        echo "  見つかりません"
    fi
    
    # Pod状態
    echo ""
    echo "GPU Operator Pod状態:"
    kubectl get pods -n gpu-operator -o wide 2>/dev/null | head -20
else
    echo -e "${YELLOW}ℹ️  gpu-operator ネームスペース未作成${NC}"
fi

echo ""
echo -e "${BLUE}=== ArgoCD インストール確認 ===${NC}"
if kubectl get namespace argocd >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  ArgoCD は既にインストールされています${NC}"
    echo ""
    echo "ArgoCD Pod状態:"
    kubectl get pods -n argocd -o wide 2>/dev/null | head -10
else
    echo -e "${GREEN}✅ ArgoCD は未インストールです${NC}"
fi

echo ""
echo -e "${BLUE}=== 監視システム確認 ===${NC}"
if kubectl get namespace monitoring >/dev/null 2>&1; then
    PROMETHEUS_COUNT=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)
    if [ $PROMETHEUS_COUNT -gt 0 ]; then
        echo -e "${GREEN}✅ Prometheus検出 ($PROMETHEUS_COUNT Pods)${NC}"
    else
        echo -e "${YELLOW}ℹ️  Prometheus未検出${NC}"
    fi
else
    echo -e "${YELLOW}ℹ️  monitoring ネームスペース未作成${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ ${ENV_NAME}環境 Step 1: 環境確認完了${NC}"
echo "=========================================="
echo ""
echo "確認項目サマリー:"
echo "  - GPUノード: ${GPU_NODES[@]}"
GPU_TOTAL=0
for node in "${GPU_NODES[@]}"; do
    GPU_COUNT=$(kubectl get node $node -o jsonpath='{.status.capacity.nvidia\.com/gpu}' 2>/dev/null || echo "0")
    GPU_TOTAL=$((GPU_TOTAL + GPU_COUNT))
done
echo "  - GPU総数: $GPU_TOTAL"
echo "  - GPU Operator: $(kubectl get namespace gpu-operator >/dev/null 2>&1 && echo '導入済み' || echo '未導入')"
echo "  - 監視システム: $(kubectl get namespace monitoring >/dev/null 2>&1 && echo '導入済み' || echo '未導入')"
echo ""
