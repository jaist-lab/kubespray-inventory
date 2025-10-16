#!/bin/bash
# Metrics Server有効化スクリプト（最適化版）

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Metrics Server有効化（最適化版）"
echo "=========================================="
echo ""

# 環境選択
echo "対象環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
read -p "選択 (1 or 2): " ENV_CHOICE

case $ENV_CHOICE in
    1)
        ENV_NAME="production"
        export KUBECONFIG=~/.kube/config-production
        CONFIG_FILE="kubelet-csr-approver-config-production.yaml"
        NODE_IPS="172.16.100.101 172.16.100.102 172.16.100.103 172.16.100.111 172.16.100.112 172.16.100.113"
        ;;
    2)
        ENV_NAME="development"
        export KUBECONFIG=~/.kube/config-development
        CONFIG_FILE="kubelet-csr-approver-config-development.yaml"
        NODE_IPS="172.16.100.121 172.16.100.122 172.16.100.123 172.16.100.131 172.16.100.132 172.16.100.133"
        ;;
    *)
        echo -e "${RED}✗ 無効な選択です${NC}"
        exit 1
        ;;
esac

echo ""
echo "環境: ${ENV_NAME}"
echo ""

read -p "この環境でMetrics Serverを有効化しますか？ (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "キャンセルしました"
    exit 0
fi

# ステップ1-4: 従来通り（省略）
# ...

# ステップ5: kubelet設定最適化
echo ""
echo "=========================================="
echo "[5/8] kubelet設定最適化"
echo "=========================================="

for node in $NODE_IPS; do
    echo "  $node: serverTLSBootstrap確認中..."
    
    if ! ssh jaist-lab@$node "sudo grep -q 'serverTLSBootstrap: true' /var/lib/kubelet/config.yaml" 2>/dev/null; then
        echo "    設定追加中..."
        ssh jaist-lab@$node "sudo sed -i '/rotateCertificates:/a serverTLSBootstrap: true' /var/lib/kubelet/config.yaml"
        echo "    ✓ 追加完了"
    else
        echo "    ✓ 既に設定済み"
    fi
done

echo -e "${GREEN}✓ kubelet設定最適化完了${NC}"

# ステップ6: kubelet順次再起動
echo ""
echo "=========================================="
echo "[6/8] 全ノードkubelet順次再起動"
echo "=========================================="
echo ""
echo "⚠ API Server負荷分散のため10秒間隔で再起動します"
echo ""

NODE_COUNT=0
TOTAL_NODES=$(echo $NODE_IPS | wc -w)

for node in $NODE_IPS; do
    NODE_COUNT=$((NODE_COUNT + 1))
    echo "[$NODE_COUNT/$TOTAL_NODES] $node"
    
    ssh jaist-lab@$node "sudo systemctl restart kubelet" && \
        echo -e "${GREEN}  ✓ 成功${NC}" || \
        echo -e "${RED}  ✗ 失敗${NC}"
    
    if [ $NODE_COUNT -lt $TOTAL_NODES ]; then
        sleep 10
    fi
done

echo ""
echo -e "${GREEN}✓ 全ノード再起動完了${NC}"
echo ""
echo "CSR生成・処理待機（60秒）..."
sleep 60

# ステップ7: CSR段階的承認
echo ""
echo "=========================================="
echo "[7/8] CSR段階的承認"
echo "=========================================="

for attempt in 1 2 3; do
    echo ""
    echo "--- 試行 $attempt/3 ---"
    
    PENDING_CSRS=$(kubectl get csr 2>/dev/null | grep "Pending" | awk '{print $1}')
    PENDING_COUNT=$(echo "$PENDING_CSRS" | grep -c "csr-" 2>/dev/null || echo "0")
    
    if [ "$PENDING_COUNT" -gt 0 ]; then
        echo "Pending CSR: ${PENDING_COUNT}個 - 承認中..."
        
        for csr in $PENDING_CSRS; do
            kubectl certificate approve $csr 2>/dev/null && \
                echo "  ✓ $csr" || \
                echo "  ✗ $csr"
        done
        
        if [ $attempt -lt 3 ]; then
            echo "証明書発行待機（30秒）..."
            sleep 30
        fi
    else
        echo "✓ Pending CSRなし"
        break
    fi
done

# 証明書確認
echo ""
echo "証明書生成確認:"
CERT_SUCCESS=0
for node in $NODE_IPS; do
    if ssh jaist-lab@$node "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo -e "${GREEN}✓ $node${NC}"
        CERT_SUCCESS=$((CERT_SUCCESS + 1))
    else
        echo -e "${RED}✗ $node${NC}"
    fi
done

TOTAL_NODES=$(echo $NODE_IPS | wc -w)
echo ""
echo "証明書生成: ${CERT_SUCCESS} / ${TOTAL_NODES} ノード"

# ステップ8: Metrics Server起動
echo ""
echo "=========================================="
echo "[8/8] Metrics Server起動"
echo "=========================================="

if [ ${CERT_SUCCESS} -gt 0 ]; then
    kubectl delete pod -n kube-system -l app.kubernetes.io/name=metrics-server
    echo "起動待機（60秒）..."
    sleep 60
    
    kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
    
    # 動作確認
    echo ""
    if kubectl top nodes 2>/dev/null; then
        echo -e "${GREEN}✓ Metrics Server動作確認成功${NC}"
    else
        echo -e "${RED}✗ Metrics Server動作確認失敗${NC}"
    fi
else
    echo -e "${RED}✗ 証明書未生成のためスキップ${NC}"
fi

echo ""
echo "=========================================="
echo "処理完了"
echo "=========================================="
echo "証明書生成: ${CERT_SUCCESS} / ${TOTAL_NODES}"
echo "=========================================="
