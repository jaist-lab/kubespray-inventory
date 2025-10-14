#!/bin/bash
# デプロイ後のmetrics-server自動セットアップ

set -e

echo "=========================================="
echo "Post-Deploy: Metrics Server Setup"
echo "=========================================="

# 環境選択
echo "セットアップする環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
read -p "選択 (1/2): " ENV_CHOICE

case $ENV_CHOICE in
    1)
        export KUBECONFIG=~/.kube/config-production
        NODES="101 102 103 111 112 113"
        NODE_PREFIX="172.16.100."
        ENV_NAME="Production"
        ;;
    2)
        export KUBECONFIG=~/.kube/config-development
        NODES="121 122 123 131 132 133"
        NODE_PREFIX="172.16.100."
        ENV_NAME="Development"
        ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

echo ""
echo "環境: ${ENV_NAME}"
echo ""

# [1/6] kubelet-csr-approver ConfigMap確認
echo "[1/6] kubelet-csr-approver ConfigMap確認..."
if kubectl get cm -n kube-system kubelet-csr-approver &>/dev/null; then
    echo "✓ ConfigMap存在確認"
    echo ""
    echo "ConfigMap内容:"
    kubectl get cm -n kube-system kubelet-csr-approver -o yaml | grep -A 10 "config.yaml:"
else
    echo "✗ ConfigMapが存在しません"
    echo "エラー: デプロイスクリプトが正常に完了していない可能性があります"
    exit 1
fi

# [2/6] 既存のDenied CSRを削除
echo ""
echo "[2/6] 既存のDenied CSRをクリーンアップ..."
DENIED_COUNT=$(kubectl get csr 2>/dev/null | grep -c Denied || echo 0)
if [ $DENIED_COUNT -gt 0 ]; then
    echo "Denied CSRを削除中 ($DENIED_COUNT 件)..."
    kubectl delete csr --all
    echo "✓ クリーンアップ完了"
else
    echo "✓ Denied CSRなし"
fi

# [3/6] 全ノードのkubeletを再起動
echo ""
echo "[3/6] 全ノードのkubeletを再起動..."
for node in $NODES; do
    NODE_IP="${NODE_PREFIX}${node}"
    echo "  再起動中: ${NODE_IP}"
    ssh jaist-lab@${NODE_IP} "sudo systemctl restart kubelet" 2>/dev/null || echo "    ⚠ 失敗"
    sleep 2
done

echo "✓ 全ノードのkubelet再起動完了"

# [4/6] CSR生成待機と承認
echo ""
echo "[4/6] CSR生成待機と承認..."
echo "30秒待機..."
sleep 30

kubectl get csr | head -10

PENDING_COUNT=$(kubectl get csr 2>/dev/null | grep -c Pending || echo 0)
if [ $PENDING_COUNT -gt 0 ]; then
    echo "Pending CSRを承認中 ($PENDING_COUNT 件)..."
    kubectl get csr -o name | xargs kubectl certificate approve
    echo "✓ CSR承認完了"
else
    echo "⚠ Pending CSRが見つかりません"
    echo "手動で確認してください: kubectl get csr"
fi

# [5/6] kubelet-server証明書確認
echo ""
echo "[5/6] kubelet-server証明書確認..."
SUCCESS=0
FAILED=0

for node in $NODES; do
    NODE_IP="${NODE_PREFIX}${node}"
    printf "  %-20s " "${NODE_IP}:"
    
    if ssh jaist-lab@${NODE_IP} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo "✓ 証明書生成済み"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "✗ 証明書未生成"
        FAILED=$((FAILED + 1))
    fi
done

# [6/6] metrics-server確認
echo ""
echo "[6/6] metrics-server確認..."
echo "metrics-server Podを再起動..."
kubectl delete pod -n kube-system -l app.kubernetes.io/name=metrics-server 2>/dev/null || echo "metrics-server Pod未検出"

echo ""
echo "60秒待機してmetrics-server起動を確認..."
sleep 60

# 最終確認
echo ""
echo "=========================================="
echo "セットアップ結果"
echo "=========================================="
echo "証明書生成: 成功 $SUCCESS / 失敗 $FAILED"
echo ""

kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server

echo ""
echo "メトリクス取得テスト:"
if kubectl top nodes &>/dev/null; then
    echo "✓ メトリクス取得成功"
    echo ""
    kubectl top nodes
else
    echo "✗ メトリクス取得失敗"
    echo ""
    echo "トラブルシューティング:"
    echo "  1. CSR状態確認: kubectl get csr"
    echo "  2. metrics-serverログ: kubectl logs -n kube-system -l app.kubernetes.io/name=metrics-server"
    echo "  3. 手順書「11. トラブルシューティング」を参照"
fi

echo ""
echo "=========================================="
