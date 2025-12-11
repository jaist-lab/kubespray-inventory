#!/bin/bash
# Development環境デプロイ後検証スクリプト

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRAY_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

# 環境設定
ENV_NAME="Development"
KUBECONFIG="${HOME}/.kube/config-development"
MASTER_IPS=("172.16.100.121" "172.16.100.122" "172.16.100.123")
MASTER_NAMES=("dev-master01" "dev-master02" "dev-master03")

export KUBECONFIG

echo "=========================================="
echo "${ENV_NAME}環境デプロイ後検証"
echo "=========================================="

# [1] ノード状態
echo ""
echo "[1] ノード状態"
kubectl get nodes

# [2] システムコンポーネント
echo ""
echo "[2] システムコンポーネント"
kubectl get pods -n kube-system -l tier=control-plane

# [3] CNI（Calico）
echo ""
echo "[3] CNI（Calico）"
kubectl get pods -n kube-system -l k8s-app=calico-node

# [4] CoreDNS
echo ""
echo "[4] CoreDNS"
kubectl get pods -n kube-system -l k8s-app=kube-dns

# [5] API Server健全性
echo ""
echo "[5] API Server健全性"
for master in dev-master01 dev-master02 dev-master03; do
    echo "  $master:"
    kubectl get pods -n kube-system -l component=kube-apiserver --field-selector spec.nodeName=$master
done

# [6] クラスタ情報
echo ""
echo "[6] クラスタ情報"
kubectl cluster-info

# [7] etcd情報
echo ""
echo "[7] etcd情報"

for i in "${!MASTER_IPS[@]}"; do
    IP="${MASTER_IPS[$i]}"
    NAME="${MASTER_NAMES[$i]}"
    
    echo ""
    echo " ======= ${NAME}: =========================================================================="
    echo ""
    
    # etcdサービス状態確認
    echo "etcd状態確認"
    ssh jaistlab@${IP} 'sudo systemctl status etcd' | grep -A 10 "Loaded:"
    
    # etcdディスク使用状況
    echo ""
    echo "etcdディスク使用状況"
    ssh jaistlab@${IP} "df -h /var/lib/etcd"
    
    # etcdデータベースサイズ
    echo ""
    echo "etcdデータベースサイズ"
    ssh jaistlab@${IP} "sudo du -sh /var/lib/etcd/member"
    
    # etcdctlの存在確認
    echo ""
    echo "etcdctlコマンド確認"
    ETCDCTL_PATH=$(ssh jaistlab@${IP} "which etcdctl 2>/dev/null || echo 'not_found'")
    
    if [ "$ETCDCTL_PATH" != "not_found" ]; then
        echo "✓ etcdctlインストール済み: $ETCDCTL_PATH"
        
        # etcdヘルスチェック
        echo ""
        echo "etcdヘルスチェック"
        ssh jaistlab@${IP} "
            sudo /usr/local/bin/etcdctl \
              --endpoints=https://127.0.0.1:2379 \
              --cacert=/etc/ssl/etcd/ssl/ca.pem \
              --cert=/etc/ssl/etcd/ssl/node-${NAME}.pem \
              --key=/etc/ssl/etcd/ssl/node-${NAME}-key.pem \
              endpoint health
        " 2>&1 | grep -v "Warning" || echo "ヘルスチェック実行"
        
        # etcdメンバー一覧
        echo ""
        echo "etcdメンバー一覧"
        ssh jaistlab@${IP} "
            sudo /usr/local/bin/etcdctl \
              --endpoints=https://127.0.0.1:2379 \
              --cacert=/etc/ssl/etcd/ssl/ca.pem \
              --cert=/etc/ssl/etcd/ssl/node-${NAME}.pem \
              --key=/etc/ssl/etcd/ssl/node-${NAME}-key.pem \
              member list -w table
        " 2>&1 | grep -v "Warning" || echo "メンバー一覧取得"
        
    else
        echo "✗ etcdctlが見つかりません"
        echo ""
        echo "インストールコマンド:"
        echo "  ./add-etcdctl-master-nodes.sh"
    fi
done

echo ""
echo "=========================================="
echo "✓ 検証完了"
echo "=========================================="
