#!/bin/bash
# ノード接続確認スクリプト（v2.28.0対応）

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
    
    # Ansible Ping
    echo "[1/3] Ansible Ping テスト..."
    cd "${KUBESPRAY_DIR}"
    ansible -i "${INVENTORY_DIR}/hosts.yml" all -m ping -o
    
    # ホスト名確認
    echo ""
    echo "[2/3] ホスト名確認..."
    ansible -i "${INVENTORY_DIR}/hosts.yml" all -a "hostname" -o
    
    # システム情報確認
    echo ""
    echo "[3/3] システム情報確認..."
    ansible -i "${INVENTORY_DIR}/hosts.yml" all -m setup -a "filter=ansible_distribution*" -o
}

case $ENV_CHOICE in
    1)
        check_environment "Production" "${KUBESPRAY_DIR}/inventory/production"
        export KUBECONFIG=~/.kube/config-production

        # dlcsv1にTaint設定
        echo "dlcsv1にTaint設定中..."
        if kubectl taint node dlcsv1 dedicated=gpu-compute:NoSchedule --overwrite; then
            echo -e "${GREEN}✅ dlcsv1: Taint設定成功${NC}"
            kubectl describe node dlcsv1 | grep -A 5 Taints
        else
            echo -e "${RED}❌ dlcsv1: Taint設定失敗${NC}"
            exit 1
        fi

        # dlcsv2にTaint設定
        echo ""
        echo "dlcsv2にTaint設定中..."
        if kubectl taint node dlcsv2 dedicated=gpu-compute:NoSchedule --overwrite; then
            echo -e "${GREEN}✅ dlcsv2: Taint設定成功${NC}"
            kubectl describe node dlcsv2 | grep -A 5 Taints

        else
            echo -e "${RED}❌ dlcsv2: Taint設定失敗${NC}"
            exit 1
        fi
        ;;
    2)
        check_environment "Development" "${KUBESPRAY_DIR}/inventory/development"
        export KUBECONFIG=~/.kube/config-development

        # rtxsv1にTaint設定
        echo "rtxsv1にTaint設定中..."
        if kubectl taint node rtxsv1 dedicated=gpu-compute:NoSchedule --overwrite; then
            echo -e "${GREEN}✅ rtxsv1: Taint設定成功${NC}"
            kubectl describe node rtxsv1 | grep -A 5 Taints
        else
            echo -e "${RED}❌ rtxsv1: Taint設定失敗${NC}"
            exit 1
        fi
        ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "✓ 接続確認完了"
echo "=========================================="
