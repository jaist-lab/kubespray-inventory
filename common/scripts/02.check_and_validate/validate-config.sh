#!/bin/bash
# Kubespray設定検証スクリプト

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

echo "=========================================="
echo "Kubespray設定検証"
echo "=========================================="

# 環境選択
echo "検証する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
read -p "選択 (1 or 2): " ENV_CHOICE

case $ENV_CHOICE in
    1)
        INVENTORY_DIR="${KUBESPRAY_DIR}/inventory/production"
        ENV_NAME="Production"
        ;;
    2)
        INVENTORY_DIR="${KUBESPRAY_DIR}/inventory/development"
        ENV_NAME="Development"
        ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

echo ""
echo "環境: ${ENV_NAME}"
echo "Inventory: ${INVENTORY_DIR}"
echo ""

# 仮想環境確認
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "エラー: Python仮想環境が有効化されていません"
    exit 1
fi

cd "${KUBESPRAY_DIR}"

# hosts.yml存在確認
echo "[1/6] hosts.yml確認..."
if [ ! -f "${INVENTORY_DIR}/hosts.yml" ]; then
    echo "✗ hosts.yml が見つかりません"
    exit 1
fi
echo "✓ hosts.yml 存在確認OK"

# Inventory構文チェック
echo ""
echo "[2/6] Inventory構文チェック..."
ansible-inventory -i "${INVENTORY_DIR}/hosts.yml" --list > /dev/null
echo "✓ Inventory構文OK"

# 必須グループ確認
echo ""
echo "[3/6] 必須グループ確認..."
REQUIRED_GROUPS="kube_control_plane kube_node etcd k8s_cluster"
for group in $REQUIRED_GROUPS; do
    if ansible-inventory -i "${INVENTORY_DIR}/hosts.yml" --list | grep -q "\"$group\""; then
        echo "  ✓ $group"
    else
        echo "  ✗ $group が見つかりません"
        exit 1
    fi
done

# group_vars確認
echo ""
echo "[4/6] group_vars設定ファイル確認..."
REQUIRED_FILES="group_vars/all/all.yml group_vars/k8s_cluster/k8s-cluster.yml group_vars/k8s_cluster/addons.yml group_vars/k8s_cluster/k8s-net-calico.yml"
for file in $REQUIRED_FILES; do
    if [ -f "${INVENTORY_DIR}/${file}" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file が見つかりません"
        exit 1
    fi
done

# YAML構文チェック
echo ""
echo "[5/6] YAML構文チェック..."
python3 -c "import yaml; yaml.safe_load(open('${INVENTORY_DIR}/hosts.yml'))" && echo "✓ YAML構文OK"

# ネットワーク設定確認
echo ""
echo "[6/6] ネットワーク設定確認..."
SERVICE_SUBNET=$(grep "kube_service_addresses:" "${INVENTORY_DIR}/group_vars/k8s_cluster/k8s-cluster.yml" | awk '{print $2}')
POD_SUBNET=$(grep "kube_pods_subnet:" "${INVENTORY_DIR}/group_vars/k8s_cluster/k8s-cluster.yml" | awk '{print $2}')
echo "  Service Subnet: ${SERVICE_SUBNET}"
echo "  Pod Subnet: ${POD_SUBNET}"

# Production/Development間の重複チェック
if [ "$ENV_NAME" == "Production" ]; then
    DEV_SERVICE=$(grep "kube_service_addresses:" "${KUBESPRAY_DIR}/inventory/development/group_vars/k8s_cluster/k8s-cluster.yml" 2>/dev/null | awk '{print $2}')
    DEV_POD=$(grep "kube_pods_subnet:" "${KUBESPRAY_DIR}/inventory/development/group_vars/k8s_cluster/k8s-cluster.yml" 2>/dev/null | awk '{print $2}')
    
    if [ "$SERVICE_SUBNET" == "$DEV_SERVICE" ] || [ "$POD_SUBNET" == "$DEV_POD" ]; then
        echo "  ✗ 警告: Development環境とサブネットが重複しています"
    else
        echo "  ✓ サブネット重複なし"
    fi
fi

echo ""
echo "=========================================="
echo "✓ 設定検証完了"
echo "=========================================="
echo ""
echo "次のステップ:"
echo "  1. ノード接続確認: ./check-nodes.sh"
echo "  2. デプロイ実行: ./deploy-${ENV_NAME,,}.sh"
