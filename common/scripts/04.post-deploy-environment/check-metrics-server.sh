#!/bin/bash
# Metrics Server ヘルスチェックスクリプト

set -e

echo "=========================================="
echo "Metrics Server Health Check"
echo "=========================================="

# 環境選択
echo "確認する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
read -p "選択 (1/2): " ENV_CHOICE

case $ENV_CHOICE in
    1)
        export KUBECONFIG=~/.kube/config-production
        NODES="111 112 113"
        NODE_PREFIX="172.16.100."
        ;;
    2)
        export KUBECONFIG=~/.kube/config-development
        NODES="131 132 133"
        NODE_PREFIX="172.16.100."
        ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

echo ""
echo "[1/5] metrics-server Pod状態確認"
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server

POD_STATUS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
POD_READY=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

if [ "$POD_STATUS" == "Running" ] && [ "$POD_READY" == "True" ]; then
    echo "✓ metrics-server Pod: OK"
else
    echo "✗ metrics-server Pod: FAILED (Status: $POD_STATUS, Ready: $POD_READY)"
    exit 1
fi

echo ""
echo "[2/5] kubelet-server証明書確認"
for node in $NODES; do
    NODE_IP="${NODE_PREFIX}${node}"
    printf "%-20s " "${NODE_IP}:"
    
    if ssh jaist-lab@${NODE_IP} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo "✓ 証明書あり"
    else
        echo "✗ 証明書なし"
    fi
done

echo ""
echo "[3/5] kubelet-csr-approver ConfigMap確認"
kubectl get cm -n kube-system kubelet-csr-approver -o yaml | grep -A 10 "config.yaml:" | head -12

echo ""
echo "[4/5] CSR状態確認"
PENDING_CSR=$(kubectl get csr 2>/dev/null | grep -c Pending || echo 0)
DENIED_CSR=$(kubectl get csr 2>/dev/null | grep -c Denied || echo 0)

echo "Pending CSR: $PENDING_CSR"
echo "Denied CSR: $DENIED_CSR"

if [ $DENIED_CSR -gt 0 ]; then
    echo "⚠ 警告: Denied CSRが存在します"
    kubectl get csr | grep Denied | head -5
fi

echo ""
echo "[5/5] kubectl top nodes テスト"
if kubectl top nodes &>/dev/null; then
    echo "✓ メトリクス取得: OK"
    kubectl top nodes
else
    echo "✗ メトリクス取得: FAILED"
    exit 1
fi

echo ""
echo "=========================================="
echo "✓ Metrics Server Health Check Complete"
echo "=========================================="
