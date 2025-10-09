#!/bin/bash

echo "=========================================="
echo "nginx-proxy診断"
echo "=========================================="
echo ""

echo "[1] nginx-proxy Pod状態"
sudo crictl ps -a | grep nginx-proxy

echo ""
echo "[2] nginx-proxy ログ（最新20行）"
CONTAINER=$(sudo crictl ps -a | grep nginx-proxy | awk '{print $1}' | head -1)
if [ -n "$CONTAINER" ]; then
    sudo crictl logs $CONTAINER 2>&1 | tail -20
else
    echo "  コンテナが見つかりません"
fi

echo ""
echo "[3] nginx設定ファイル"
if [ -f /etc/kubernetes/nginx-proxy.conf ]; then
    echo "  upstream設定:"
    sudo grep -A 5 "upstream kubernetes" /etc/kubernetes/nginx-proxy.conf
else
    echo "  設定ファイルが見つかりません"
fi

echo ""
echo "[4] API Server接続テスト"
for ip in 172.16.100.{101..103}; do
    echo -n "  $ip:6443 ... "
    timeout 2 bash -c "echo > /dev/tcp/$ip/6443" 2>/dev/null && \
        echo "OK" || echo "NG"
done

echo ""
echo "[5] localhost:6443接続テスト"
timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/6443" 2>/dev/null && \
    echo "  OK" || echo "  NG"

echo ""
echo "=========================================="
