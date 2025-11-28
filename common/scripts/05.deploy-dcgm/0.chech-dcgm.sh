#!/bin/bash
# 環境確認スクリプト（完全自動検出版）

echo "🔍 GPU環境確認（完全自動検出版）"
echo "=============================="

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "ノード接続確認"
echo "=========================================="

# 環境選択
echo "GPU用のTaintを設定する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"

read -p "選択 (1/2): " ENV_CHOICE

check_environment() {
    local ENV_NAME=$1
    local INVENTORY_DIR=$2
    
    echo ""
    echo "=========================================="
    echo "${ENV_NAME}環境確認"
    echo "=========================================="
    echo "Inventory: ${INVENTORY_DIR}"
    echo "Taint: dedicated=gpu-compute:NoSchedule"
    echo ""
    
    # 仮想環境確認
    if [[ "$VIRTUAL_ENV" == "" ]]; then
        echo "エラー: Python仮想環境が有効化されていません"
        echo "実行: source ~/kubernetes/venv/bin/activate"
        exit 1
    fi
    
    # ホスト名確認
    echo ""
    echo "ホスト名確認..."
    ansible -i "${INVENTORY_DIR}/hosts.yml" all -a "hostname" -o
    echo ""
    echo ""
}

# 環境別の設定
case $ENV_CHOICE in
    1)
        check_environment "Production" "${KUBESPRAY_DIR}/inventory/production"
        export KUBECONFIG=~/.kube/config-production
        # Productionの対象ノード
        GPU_NODES=("dlp1" "dlp2")
        GPU_NODE_IPS=("172.16.100.41" "172.16.100.42")
        ;;
    2)
        check_environment "Development" "${KUBESPRAY_DIR}/inventory/development"
        export KUBECONFIG=~/.kube/config-development
        # Developmentの対象ノード
        GPU_NODES=("dlcsv1" "dlcsv2")
        GPU_NODE_IPS=("172.16.100.31" "172.16.100.32")
        ;;
    *)
        echo -e "${RED}無効な選択肢です。1または2を選択してください。${NC}"
        exit 1
        ;;
esac

echo "=========================================="
echo ""

# 以降の処理で環境別の設定を使用
# =======================================
# GPU環境確認処理
# =======================================

# Kubernetesクラスター状態確認
echo "📊 Kubernetesクラスター状態:"
kubectl get nodes -o wide

# 手動ラベル確認（削除対象）
echo ""
echo "🏷️ 手動ラベル確認（削除予定）:"
kubectl get nodes ${GPU_NODES[@]} --show-labels 2>/dev/null | grep -E "(workload-type|dedicated)" || echo "手動ラベルなし"

# 手動Taint確認（削除対象）
echo ""
echo "🔒 手動Taint確認（削除予定）:"
kubectl get nodes ${GPU_NODES[@]} -o custom-columns="NAME:.metadata.name,TAINTS:.spec.taints[*].key" 2>/dev/null | grep -E "(dedicated|gpu-compute)" || echo "手動Taintなし"

# Helm確認
echo ""
echo "📦 Helm状態確認:"
helm version --short

# 監視システム確認
echo ""
echo "📊 監視システム確認:"
PROMETHEUS_EXISTS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)
if [ $PROMETHEUS_EXISTS -gt 0 ]; then
    echo "✅ Prometheus監視システム検出 - 監視統合を有効化します"
    kubectl get svc -n monitoring | grep prometheus
else
    echo "ℹ️ Prometheus監視システム未検出 - GPU Operator単体で進行します"
fi

# 自動検出の前提確認
echo ""
echo "🔍 GPU自動検出の前提確認:"
echo "NVIDIA GPUハードウェアの存在確認..."
for i in "${!GPU_NODES[@]}"; do
    node_name="${GPU_NODES[$i]}"
    node_ip="${GPU_NODE_IPS[$i]}"
    gpu_check=$(ssh jaist-lab@$node_ip "lspci | grep -i nvidia | wc -l" 2>/dev/null || echo "0")
    echo "  $node_name ($node_ip): NVIDIA デバイス ${gpu_check}個検出"
done

echo ""
echo "✅ 環境確認完了 - 完全自動検出モードで進行します"
