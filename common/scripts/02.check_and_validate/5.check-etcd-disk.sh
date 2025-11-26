#!/bin/bash
# etcdディスク確認スクリプト

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

echo "=========================================="
echo "etcdディスク確認"
echo "=========================================="

# 環境選択
echo "確認する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo "  3) Sandbox"
read -p "選択 (1/2/3): " ENV_CHOICE

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

echo ""
echo "環境: ${ENV_NAME}"
echo ""

cd "${KUBESPRAY_DIR}"

# Masterノードのみ対象
echo "[1/3] Masterノードでのetcdディスク確認..."
ansible kube_control_plane -i "${INVENTORY_DIR}/hosts.yml" \
    -m shell \
    -a "df -h /var/lib/etcd && lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E '(sdb|etcd)'" \
    -o

echo ""
echo "[2/3] etcd用systemdサービス確認..."
ansible kube_control_plane -i "${INVENTORY_DIR}/hosts.yml" \
    -m shell \
    -a "systemctl status setup-etcd-disk.service | grep -E '(Active|Loaded)'" \
    -o

echo ""
echo "[3/3] etcdディスクのパフォーマンステスト（簡易）..."
ansible kube_control_plane -i "${INVENTORY_DIR}/hosts.yml" \
    -m shell \
    -a "dd if=/dev/zero of=/var/lib/etcd/test.tmp bs=1M count=100 conv=fsync 2>&1 | tail -1; rm -f /var/lib/etcd/test.tmp" \
    -o

echo ""
echo "=========================================="
echo "✓ etcdディスク確認完了"
echo "=========================================="
echo ""
echo "確認内容:"
echo "  - /var/lib/etcdが正しくマウントされているか"
echo "  - etcdディスクのサイズと種類"
echo "  - 自動マウントサービスの状態"
echo "  - ディスク書き込み性能"
echo ""
echo "次のステップ:"
echo "  全ての確認が成功していれば、Kubesprayデプロイを実行できます"
