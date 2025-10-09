#!/bin/bash
# Production環境の安全なリセット

set -e

INVENTORY="~/kubernetes/kubespray/inventory/production/hosts.yml"

echo "=========================================="
echo "Step 1: 完全リセット"
echo "=========================================="
ansible-playbook -i ${INVENTORY}  \
    --become \
    --become-user=root \
    reset.yml

# 2. 全ての証明書とKubernetes設定を削除
echo ""
echo "=========================================="
echo "Step 2: 証明書とKubernetes設定を削除"
echo "=========================================="
for host in master01 master02 master03 node01 node02 node03; do
    echo "Cleaning $host..."
    ssh jaist-lab@$host "sudo rm -rf /etc/kubernetes/ /etc/ssl/etcd/ /var/lib/etcd/ /var/lib/kubelet/ /etc/cni/"
done


# 3. 全ノード再起動
echo ""
echo "=========================================="
echo "Step 3: 全ノード再起動"
echo "=========================================="
ansible -i ${INVENTORY}  all -become -a "reboot"

# 待機
echo "Waiting 180 seconds for nodes to restart..."
sleep 180

# 4. SSH接続確認
echo ""
echo "=========================================="
echo "Step 4: SSH接続確認"
echo "=========================================="
for host in master01 master02 master03 node01 node02 node03; do
    if ssh -o ConnectTimeout=5 jaist-lab@$host "hostname" &>/dev/null; then
        echo "✓ $host: OK"
    else
        echo "✗ $host: FAILED"
    fi
done

echo ""
echo "=========================================="
echo "✓ リセット完了(Production)"
echo "=========================================="

# 全ノード再起動
ansible -i ${INVENTORY} all -become -a "reboot"