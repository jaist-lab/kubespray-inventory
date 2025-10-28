#!/bin/bash
# 全ノードSSH接続確認

echo "=========================================="
echo "Production環境 SSH接続確認"
echo "=========================================="
PROD_HOSTS="master01 master02 master03 node01 node02 dlcsv1 dlcsv2 "
PROD_FAILED=""

for host in $PROD_HOSTS; do
    if ssh -o ConnectTimeout=5 -o BatchMode=yes jaist-lab@$host "hostname" &>/dev/null; then
        echo "✓ $host: OK"
    else
        echo "✗ $host: FAILED"
        PROD_FAILED="$PROD_FAILED $host"
    fi
done

echo ""
echo "=========================================="
echo "Development環境 SSH接続確認"
echo "=========================================="
DEV_HOSTS="dev-master01 dev-master02 dev-master03 dev-node01 dev-node02 "
DEV_FAILED=""

for host in $DEV_HOSTS; do
    if ssh -o ConnectTimeout=5 -o BatchMode=yes jaist-lab@$host "hostname" &>/dev/null; then
        echo "✓ $host: OK"
    else
        echo "✗ $host: FAILED"
        DEV_FAILED="$DEV_FAILED $host"
    fi
done

echo ""
echo "=========================================="
echo "Sandbox環境 SSH接続確認"
echo "=========================================="
DEV_HOSTS="sandbox-master01 sandbox-master02 sandbox-master03 sandbox-node01 sandbox-node02 "
DEV_FAILED=""

for host in $DEV_HOSTS; do
    if ssh -o ConnectTimeout=5 -o BatchMode=yes jaist-lab@$host "hostname" &>/dev/null; then
        echo "✓ $host: OK"
    else
        echo "✗ $host: FAILED"
        SANDBOX_FAILED="$DEV_FAILED $host"
    fi
done

echo ""
echo "=========================================="
echo "結果サマリー"
echo "=========================================="
if [ -z "$PROD_FAILED" ] && [ -z "$DEV_FAILED" ]; then
    echo "✓ 全ノード接続成功"
    exit 0
else
    echo "✗ 接続失敗ノードあり"
    [ -n "$PROD_FAILED" ] && echo "Production:$PROD_FAILED"
    [ -n "$DEV_FAILED" ] && echo "Development:$DEV_FAILED"
    [ -n "$SANDBOX_FAILED" ] && echo "Sandbox:$SANDBOX_FAILED"
    exit 1
fi
