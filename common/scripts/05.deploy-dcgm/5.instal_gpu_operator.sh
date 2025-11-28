#!/bin/bash
# GPU Operatorインストールスクリプト（環境別対応・監視統合対応版）

echo "🚀 NVIDIA GPU Operator インストール開始（監視統合対応版）"
echo "========================================================"

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 環境選択
echo "GPU Operatorをインストールする環境を選択してください:"
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
        GPU_NODE_IPS=("172.16.100.31" "172.16.100.32")
        ENV_NAME="Production"
        VALUES_FILE="gpu-operator-values-production.yaml"
        ;;
    2)
        echo -e "${GREEN}Development環境を選択${NC}"
        export KUBECONFIG=~/.kube/config-development
        GPU_NODES=("rtxsv1")
        GPU_NODE_IPS=("172.16.100.41")
        ENV_NAME="Development"
        VALUES_FILE="gpu-operator-values-development.yaml"
        ;;
    *)
        echo -e "${RED}無効な選択肢です。1または2を選択してください。${NC}"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "${ENV_NAME}環境 GPU Operatorインストール"
echo "対象ノード: ${GPU_NODES[@]}"
echo "Values File: ${VALUES_FILE}"
echo "=========================================="
echo ""

# 前提条件確認
echo -e "${BLUE}📋 前提条件確認...${NC}"
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}❌ Kubernetesクラスターに接続できません${NC}"
    echo "KUBECONFIG: $KUBECONFIG"
    exit 1
fi
echo -e "${GREEN}✅ Kubernetesクラスター接続成功${NC}"

if ! command -v helm >/dev/null 2>&1; then
    echo -e "${RED}❌ Helmがインストールされていません${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Helm確認完了${NC}"

# Values Fileの存在確認
if [ ! -f "$VALUES_FILE" ]; then
    echo -e "${YELLOW}⚠️  ${VALUES_FILE} が見つかりません${NC}"
    echo "デフォルトのgpu-operator-values.yamlを使用しますか?"
    read -p "(y/N): " USE_DEFAULT
    if [[ "$USE_DEFAULT" =~ ^[Yy]$ ]]; then
        VALUES_FILE="gpu-operator-values.yaml"
        if [ ! -f "$VALUES_FILE" ]; then
            echo -e "${RED}❌ ${VALUES_FILE} も見つかりません${NC}"
            exit 1
        fi
    else
        exit 1
    fi
fi
echo -e "${GREEN}✅ Values File確認: ${VALUES_FILE}${NC}"

# 監視システム確認
echo ""
echo -e "${BLUE}🔍 監視システム確認...${NC}"
PROMETHEUS_EXISTS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)
if [ $PROMETHEUS_EXISTS -gt 0 ]; then
    echo -e "${GREEN}✅ Prometheusが稼働中です（監視統合を有効化）${NC}"
    MONITORING_INTEGRATION=true
else
    echo -e "${YELLOW}⚠️  Prometheusが見つかりません（監視統合を無効化）${NC}"
    MONITORING_INTEGRATION=false
fi

# GPU検出確認（ハードウェアレベル）
echo ""
echo -e "${BLUE}🔍 GPU自動検出確認...${NC}"
GPU_DETECTION=false
for i in "${!GPU_NODE_IPS[@]}"; do
    node_name="${GPU_NODES[$i]}"
    node_ip="${GPU_NODE_IPS[$i]}"
    gpu_count=$(ssh jaist-lab@$node_ip "lspci | grep -i nvidia | wc -l" 2>/dev/null || echo "0")
    if [ "$gpu_count" -gt 0 ]; then
        echo -e "${GREEN}✅ ${node_name} (${node_ip}): NVIDIA GPU ${gpu_count}個検出${NC}"
        GPU_DETECTION=true
    else
        echo -e "${YELLOW}⚠️  ${node_name} (${node_ip}): NVIDIA GPU未検出${NC}"
    fi
done

if [ "$GPU_DETECTION" = false ]; then
    echo -e "${RED}❌ GPUハードウェアが検出されません${NC}"
    exit 1
fi

# 既存GPU Operator削除確認
echo ""
echo -e "${BLUE}🧹 既存GPU Operator確認...${NC}"
if helm list -n gpu-operator | grep -q gpu-operator; then
    echo -e "${YELLOW}既存のGPU Operatorが見つかりました${NC}"
    helm list -n gpu-operator
    echo ""
    read -p "既存のGPU Operatorを削除して再インストールしますか? (y/N): " UNINSTALL
    if [[ "$UNINSTALL" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}🗑️  既存GPU Operator削除中...${NC}"
        helm uninstall gpu-operator -n gpu-operator
        echo -e "${GREEN}✅ 削除完了${NC}"
        echo "リソースクリーンアップ待機中（30秒）..."
        sleep 30
    else
        echo -e "${YELLOW}インストールをキャンセルしました${NC}"
        exit 0
    fi
else
    echo -e "${GREEN}✅ 既存リリースなし（新規インストール）${NC}"
fi

# GPU Operatorインストール
echo ""
echo "=========================================="
echo -e "${BLUE}🚀 GPU Operatorインストール開始${NC}"
echo "環境: ${ENV_NAME}"
echo "Values: ${VALUES_FILE}"
echo "（この処理には10-15分程度かかります）"
echo "=========================================="
echo ""

helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 20m

INSTALL_RESULT=$?

if [ $INSTALL_RESULT -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ GPU Operatorインストール完了!${NC}"
    
    # 監視統合設定（Prometheusが存在する場合）
    if [ "$MONITORING_INTEGRATION" = true ]; then
        echo ""
        echo -e "${BLUE}🔗 監視システム統合設定開始...${NC}"
        
        # Pod起動待ち
        echo "DCGM Exporter起動待ち（60秒）..."
        sleep 60
        
        # DCGM Exporter Service確認
        echo ""
        echo "DCGM Exporter Service確認:"
        kubectl get svc -n gpu-operator -l app=nvidia-dcgm-exporter
        
        # ServiceMonitor作成
        echo ""
        echo "ServiceMonitor作成中..."
        if [ -f "dcgm-servicemonitor.yaml" ]; then
            kubectl apply -f dcgm-servicemonitor.yaml
            echo -e "${GREEN}✅ ServiceMonitor作成完了${NC}"
        else
            echo -e "${YELLOW}⚠️  dcgm-servicemonitor.yaml が見つかりません${NC}"
        fi

        # Prometheus設定更新
        echo ""
        echo "Prometheus設定更新中..."
        kubectl patch prometheus -n monitoring prometheus-cluster-kube-prometheus-prometheus --type='merge' -p='{
            "spec": {
                "serviceMonitorNamespaceSelector": {
                    "matchNames": ["monitoring", "gpu-operator", "kube-system"]
                }
            }
        }' 2>/dev/null && echo -e "${GREEN}✅ Prometheus設定更新完了${NC}" || echo -e "${YELLOW}⚠️  Prometheus設定更新スキップ${NC}"
        
        echo -e "${GREEN}✅ 監視システム統合設定完了${NC}"
    fi
    
else
    echo ""
    echo -e "${RED}❌ GPU Operatorインストール失敗${NC}"
    echo ""
    echo "最近のイベント:"
    kubectl get events -n gpu-operator --sort-by='.lastTimestamp' | tail -10
    exit 1
fi

# インストール状況確認
echo ""
echo "=========================================="
echo -e "${BLUE}📊 インストール状況確認...${NC}"
echo "=========================================="
kubectl get pods -n gpu-operator

echo ""
echo -e "${GREEN}🎉 ${ENV_NAME}環境 完全自動検出インストール完了!${NC}"

# 監視統合確認
if [ "$MONITORING_INTEGRATION" = true ]; then
    echo ""
    echo "=========================================="
    echo -e "${BLUE}📊 監視統合状況確認${NC}"
    echo "=========================================="
    
    echo "ServiceMonitor確認:"
    kubectl get servicemonitor -n monitoring nvidia-dcgm-exporter 2>/dev/null || echo -e "${YELLOW}ServiceMonitor未作成${NC}"
    
    echo ""
    echo "5分後にPrometheus Targetsで確認してください:"
    # 最初のノードのIPを取得
    FIRST_NODE="${GPU_NODES[0]}"
    NODE_IP=$(kubectl get node "$FIRST_NODE" -o jsonpath='{.status.addresses[0].address}' 2>/dev/null)
    if [ -n "$NODE_IP" ]; then
        echo -e "  ${BLUE}Prometheus: http://${NODE_IP}:32090/targets${NC}"
    else
        echo "  ノードIPの取得に失敗しました"
    fi
fi

echo ""
echo "=========================================="
echo "次のステップ:"
echo "  1. Pod状態確認: kubectl get pods -n gpu-operator"
echo "  2. GPU検出確認: kubectl get nodes -o json | jq '.items[].status.capacity'"
echo "  3. テストPod実行でGPU動作確認"
echo "=========================================="