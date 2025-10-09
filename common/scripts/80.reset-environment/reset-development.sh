#!/bin/bash
# Development環境の安全なリセット

set -e

INVENTORY="../../../development/hosts.yml"

echo "=========================================="
echo "Development環境 安全リセット"
echo "=========================================="
echo ""

# UFW一時停止
echo "[1/7] UFW一時停止..."
ansible -i ${INVENTORY} all --become -m systemd -a "name=ufw state=stopped" || true

# サービス停止
echo ""
echo "[2/7] サービス停止..."
ansible -i ${INVENTORY} all --become -m systemd -a "name=kubelet state=stopped" || true
ansible -i ${INVENTORY} all --become -m systemd -a "name=etcd state=stopped" || true

# コンテナ削除
echo ""
echo "[3/7] コンテナ削除..."
ansible -i ${INVENTORY} all --become -m shell -a "crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock stop \$(crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -q) 2>/dev/null || true"
ansible -i ${INVENTORY} all --become -m shell -a "crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock rm \$(crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a -q) 2>/dev/null || true"
ansible -i ${INVENTORY} all --become -m shell -a "crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock stopp \$(crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock pods -q) 2>/dev/null || true"
ansible -i ${INVENTORY} all --become -m shell -a "crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock rmp \$(crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock pods -q) 2>/dev/null || true"

# Kubernetes設定削除
echo ""
echo "[4/7] Kubernetes設定削除..."
ansible -i ${INVENTORY} all --become -m shell -a "rm -rf /etc/kubernetes/manifests/* /etc/kubernetes/*.conf /etc/kubernetes/ssl/* /etc/kubernetes/pki/* /var/lib/kubelet/* /var/lib/etcd/* /etc/cni/net.d/* /opt/cni/bin/*"

# containerd再起動
echo ""
echo "[5/7] containerd再起動..."
ansible -i ${INVENTORY} all --become -m systemd -a "name=containerd state=restarted"

# UFW再起動
echo ""
echo "[6/7] UFW再起動..."
ansible -i ${INVENTORY} all --become -m systemd -a "name=ufw state=started enabled=yes"

# 確認
echo ""
echo "[7/7] クリーンアップ確認..."
ansible -i ${INVENTORY} all --become -m shell -a "crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock ps -a | wc -l"

echo ""
echo "=========================================="
echo "✓ リセット完了"
echo "=========================================="
