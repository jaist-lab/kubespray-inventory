#!/bin/bash
echo "=========================================="
echo "API Server起動失敗診断"
echo "=========================================="

ssh jaist-lab@172.16.100.101 << 'REMOTE'
echo "[1] etcd状態"
sudo systemctl status etcd --no-pager

echo ""
echo "[2] etcdポート"
sudo ss -tlnp | grep 2379

echo ""
echo "[3] API Serverコンテナ"
sudo crictl ps -a | grep kube-apiserver

echo ""
echo "[4] API Serverログ（最新50行）"
CONTAINER=$(sudo crictl ps -a | grep kube-apiserver | awk '{print $1}' | head -1)
if [ -n "$CONTAINER" ]; then
    sudo crictl logs $CONTAINER 2>&1 | tail -50
else
    echo "コンテナなし"
fi

echo ""
echo "[5] kubeletログ（API Server関連）"
sudo journalctl -u kubelet --no-pager -n 50 | grep -i "apiserver\|error\|failed"

echo ""
echo "[6] 証明書確認"
ls -la /etc/kubernetes/ssl/ | head -20

echo ""
echo "[7] manifestファイル"
ls -la /etc/kubernetes/manifests/

REMOTE

echo "=========================================="
