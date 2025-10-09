#!/bin/bash
# Development環境デプロイスクリプト（v2.28.0対応）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
INVENTORY_DIR="${KUBESPRAY_DIR}/inventory/development"

echo "=========================================="
echo "Development Kubernetes Cluster デプロイ"
echo "=========================================="
echo "Kubespray Dir: ${KUBESPRAY_DIR}"
echo "Inventory Dir: ${INVENTORY_DIR}"
echo "Kubernetes Version: 1.31.3"
echo "Calico Version: v3.28.0"
echo ""

# 仮想環境確認
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "エラー: Python仮想環境が有効化されていません"
    echo "実行: source ~/kubernetes/venv/bin/activate"
    exit 1
fi

# Ansible接続確認
echo "[1/4] Ansible接続確認..."
cd "${KUBESPRAY_DIR}"
ansible -i "${INVENTORY_DIR}/hosts.yml" all -m ping -o

# Inventory検証
echo ""
echo "[2/4] Inventory検証..."
ansible-inventory -i "${INVENTORY_DIR}/hosts.yml" --list

# クラスタデプロイ
echo ""
echo "[3/4] Kubernetesクラスタデプロイ開始..."
echo "デプロイには約40-60分かかります..."
ansible-playbook -i "${INVENTORY_DIR}/hosts.yml" \
    --become \
    --become-user=root \
    -e ansible_user=jaist-lab \
    cluster.yml

# Kubeconfig取得
echo ""
echo "[4/4] Kubeconfig取得..."
mkdir -p ~/.kube
scp jaist-lab@172.16.100.121:/etc/kubernetes/admin.conf ~/.kube/config-development

# Kubeconfig権限設定
chmod 600 ~/.kube/config-development

# クラスタ確認
export KUBECONFIG=~/.kube/config-development
echo ""
echo "ノード状態確認中..."
kubectl get nodes -o wide

echo ""
echo "=========================================="
echo "✓ Development環境デプロイ完了"
echo "=========================================="
echo "Kubeconfig: ~/.kube/config-development"
echo ""
echo "次のコマンドで確認:"
echo "  export KUBECONFIG=~/.kube/config-development"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "=========================================="
