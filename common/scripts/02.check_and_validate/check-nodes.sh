#!/bin/bash
# ノード接続確認スクリプト（v2.28.0対応）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

echo "=========================================="
echo "ノード接続確認"
echo "=========================================="

# 環境選択
echo "確認する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo "  3) Sandbox"
echo "  4) すべて"
read -p "選択 (1/2/3/4): " ENV_CHOICE

check_environment() {
    local ENV_NAME=$1
    local INVENTORY_DIR=$2
    
    echo ""
    echo "=========================================="
    echo "${ENV_NAME}環境確認"
    echo "=========================================="
    echo "Inventory: ${INVENTORY_DIR}"
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
        ;;
    2)
        check_environment "Development" "${KUBESPRAY_DIR}/inventory/development"
        ;;
    3)
        check_environment "Sandbox"     "${KUBESPRAY_DIR}/inventory/development"
        ;;
    4)
        check_environment "Production" "${KUBESPRAY_DIR}/inventory/production"
        check_environment "Development" "${KUBESPRAY_DIR}/inventory/development"
        check_environment "Sandbox"     "${KUBESPRAY_DIR}/inventory/development"
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
