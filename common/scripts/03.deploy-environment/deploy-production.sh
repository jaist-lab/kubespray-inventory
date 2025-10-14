#!/bin/bash
# Production環境デプロイスクリプト（metrics-server完全対応版）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
INVENTORY_DIR="${KUBESPRAY_DIR}/inventory/production"
MASTER_IP="172.16.100.101"

echo "=========================================="
echo "Production Kubernetes Cluster デプロイ"
echo "=========================================="
echo "Kubespray Dir: ${KUBESPRAY_DIR}"
echo "Inventory Dir: ${INVENTORY_DIR}"
echo "Kubernetes Version: 1.31.3"
echo "Calico Version: v3.28.0"
echo ""
echo "⭐ kubelet-csr-approver ConfigMap 自動作成: 有効"
echo "⭐ metrics-server 自動セットアップ: 有効"
echo ""

# 仮想環境確認
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "エラー: Python仮想環境が有効化されていません"
    echo "実行: source ~/kubernetes/venv/bin/activate"
    exit 1
fi

# [1/5] Ansible接続確認
echo "[1/5] Ansible接続確認..."
cd "${KUBESPRAY_DIR}"
ansible -i "${INVENTORY_DIR}/hosts.yml" all -m ping -o

# [2/5] Inventory検証
echo ""
echo "[2/5] Inventory検証..."
ansible-inventory -i "${INVENTORY_DIR}/hosts.yml" --list > /dev/null

# [3/5] 必要なディレクトリの事前作成
echo ""
echo "[3/5] 必要なディレクトリの事前作成..."
ansible kube_control_plane -i "${INVENTORY_DIR}/hosts.yml" \
  -m shell -a "mkdir -p /etc/ssl/etcd /etc/kubernetes/ssl /etc/kubernetes/pki" \
  --become

ansible kube_control_plane -i "${INVENTORY_DIR}/hosts.yml" \
  -m shell -a "chmod 755 /etc/ssl/etcd /etc/kubernetes/ssl" \
  --become

# [4/5] Kubernetesクラスタデプロイ
echo ""
echo "[4/5] Kubernetesクラスタデプロイ開始..."
echo "⏱  デプロイには約40-60分かかります..."
echo ""
ansible-playbook -i "${INVENTORY_DIR}/hosts.yml" \
    --become \
    --become-user=root \
    -e ansible_user=jaist-lab \
    cluster.yml

# [5/5] Kubeconfig取得
echo ""
echo "[5/5] Kubeconfig取得..."
mkdir -p ~/.kube

TEMP_FILE="/tmp/admin.conf.${MASTER_IP}"

ssh jaist-lab@${MASTER_IP} "sudo cp /etc/kubernetes/admin.conf ${TEMP_FILE} && sudo chown jaist-lab:jaist-lab ${TEMP_FILE} && sudo chmod 644 ${TEMP_FILE}"
scp jaist-lab@${MASTER_IP}:${TEMP_FILE} ~/.kube/config-production
ssh jaist-lab@${MASTER_IP} "rm -f ${TEMP_FILE}"

chmod 600 ~/.kube/config-production
sed -i "s|https://127.0.0.1:6443|https://${MASTER_IP}:6443|g" ~/.kube/config-production

# クラスタ確認
export KUBECONFIG=~/.kube/config-production
echo ""
echo "ノード状態確認中..."
kubectl get nodes -o wide

echo ""
echo "=========================================="
echo "✓ Production環境デプロイ完了"
echo "=========================================="
echo "Kubeconfig: ~/.kube/config-production"
echo ""
echo "次のコマンドで確認:"
echo "  export KUBECONFIG=~/.kube/config-production"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo ""
echo "⭐ 重要: kubelet-server証明書生成とmetrics-server確認"
echo "  ./post-deploy-metrics-server.sh を実行してください"
echo "=========================================="
