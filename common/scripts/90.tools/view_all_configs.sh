#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

echo "=========================================="
echo "Kubespray 設定ファイル出力"
echo "=========================================="

# 環境選択
echo "対象の環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo "  3) Sandbox"

read -p "選択 (1 or 2 or 3): " ENV_CHOICE

case $ENV_CHOICE in
    1)
        INVENTORY_DIR="${KUBESPRAY_DIR}/inventory/production"
        ENV_NAME="Production"
        ;;
    2)
        INVENTORY_DIR="${KUBESPRAY_DIR}/inventory/development"
        ENV_NAME="Development"
        ;;
    3)
        INVENTORY_DIR="${KUBESPRAY_DIR}/inventory/sandbox"
        ENV_NAME="Sandbox"
        ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

clear
echo ""
echo "**Inventory:** ${INVENTORY_DIR}"
echo ""

cd ${INVENTORY_DIR}

~/kubernetes/kubespray/inventory/common/scripts/90.tools/view_config.sh
