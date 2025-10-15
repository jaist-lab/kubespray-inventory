#!/bin/bash
# Metrics Server検証スクリプト

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Metrics Server検証スクリプト"
echo "=========================================="
echo ""

# 環境選択
echo "検証する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
read -p "選択 (1 or 2): " ENV_CHOICE

case $ENV_CHOICE in
    1)
        ENV_NAME="production"
        export KUBECONFIG=~/.kube/config-production
        NODE_IPS="172.16.100.101 172.16.100.102 172.16.100.103 172.16.100.111 172.16.100.112 172.16.100.113"
        ;;
    2)
        ENV_NAME="development"
        export KUBECONFIG=~/.kube/config-development
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

PASSED=0
FAILED=0

# テスト1: kubelet-csr-approver
echo "=========================================="
echo "[1/10] kubelet-csr-approver状態確認"
echo "=========================================="
kubectl get pods -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver
READY_COUNT=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -c "True")
EXPECTED_COUNT=$(kubectl get deployment -n kube-system kubelet-csr-approver -o jsonpath='{.spec.replicas}')

if [ $READY_COUNT -eq $EXPECTED_COUNT ]; then
    echo -e "${GREEN}✓ PASS: kubelet-csr-approver ($READY_COUNT/$EXPECTED_COUNT)${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL: kubelet-csr-approver ($READY_COUNT/$EXPECTED_COUNT)${NC}"
    FAILED=$((FAILED + 1))
fi

# テスト2: ConfigMap
echo ""
echo "=========================================="
echo "[2/10] ConfigMap確認"
echo "=========================================="
if kubectl get cm -n kube-system kubelet-csr-approver &>/dev/null; then
    echo -e "${GREEN}✓ PASS: ConfigMapが存在します${NC}"
    PASSED=$((PASSED + 1))
    
    # ConfigMapの内容確認
    if kubectl get cm -n kube-system kubelet-csr-approver -o yaml | grep -q "bypassDNSResolution: true"; then
        echo -e "${GREEN}  └ bypassDNSResolution設定あり${NC}"
    else
        echo -e "${YELLOW}  └ WARNING: bypassDNSResolution設定なし${NC}"
    fi
else
    echo -e "${RED}✗ FAIL: ConfigMapが存在しません${NC}"
    FAILED=$((FAILED + 1))
fi

# テスト3: CSR状態
echo ""
echo "=========================================="
echo "[3/10] CSR状態確認"
echo "=========================================="
kubectl get csr 2>/dev/null | head -10
APPROVED_COUNT=$(kubectl get csr 2>/dev/null | grep -c "Approved,Issued" || echo "0")
TOTAL_COUNT=$(kubectl get csr --no-headers 2>/dev/null | wc -l)

if [ $TOTAL_COUNT -gt 0 ] && [ $APPROVED_COUNT -eq $TOTAL_COUNT ]; then
    echo -e "${GREEN}✓ PASS: すべてのCSRが承認済み ($APPROVED_COUNT/$TOTAL_COUNT)${NC}"
    PASSED=$((PASSED + 1))
elif [ $TOTAL_COUNT -eq 0 ]; then
    echo -e "${YELLOW}⚠ WARNING: CSRが存在しません${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL: 未承認のCSRがあります ($APPROVED_COUNT/$TOTAL_COUNT)${NC}"
    FAILED=$((FAILED + 1))
fi

# テスト4: kubelet-server証明書
echo ""
echo "=========================================="
echo "[4/10] kubelet-server証明書確認"
echo "=========================================="
CERT_SUCCESS=0
CERT_TOTAL=0
for node in $NODE_IPS; do
    CERT_TOTAL=$((CERT_TOTAL + 1))
    if ssh jaist-lab@$node "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo -e "${GREEN}✓ $node${NC}"
        CERT_SUCCESS=$((CERT_SUCCESS + 1))
    else
        echo -e "${RED}✗ $node${NC}"
    fi
done

if [ $CERT_SUCCESS -eq $CERT_TOTAL ]; then
    echo -e "${GREEN}✓ PASS: すべてのノードに証明書あり ($CERT_SUCCESS/$CERT_TOTAL)${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL: 証明書がないノードあり ($CERT_SUCCESS/$CERT_TOTAL)${NC}"
    FAILED=$((FAILED + 1))
fi

# テスト5: Metrics Server Pod
echo ""
echo "=========================================="
echo "[5/10] Metrics Server Pod確認"
echo "=========================================="
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
MS_READY=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

if [ "$MS_READY" == "True" ]; then
    echo -e "${GREEN}✓ PASS: Metrics Server Podが Ready${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL: Metrics Server Podが Ready ではありません${NC}"
    FAILED=$((FAILED + 1))
fi

# テスト6: Metrics Server Deployment
echo ""
echo "=========================================="
echo "[6/10] Metrics Server Deployment確認"
echo "=========================================="
kubectl get deployment -n kube-system metrics-server
MS_AVAILABLE=$(kubectl get deployment -n kube-system metrics-server -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)

if [ "$MS_AVAILABLE" == "True" ]; then
    echo -e "${GREEN}✓ PASS: Metrics Server Deploymentが Available${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL: Metrics Server Deploymentが Available ではありません${NC}"
    FAILED=$((FAILED + 1))
fi

# テスト7: APIサービス
echo ""
echo "=========================================="
echo "[7/10] Metrics Server APIサービス確認"
echo "=========================================="
kubectl get apiservice v1beta1.metrics.k8s.io
API_AVAILABLE=$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)

if [ "$API_AVAILABLE" == "True" ]; then
    echo -e "${GREEN}✓ PASS: Metrics Server APIが Available${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL: Metrics Server APIが Available ではありません${NC}"
    FAILED=$((FAILED + 1))
fi

# テスト8: ノードメトリクス取得
echo ""
echo "=========================================="
echo "[8/10] ノードメトリクス取得テスト"
echo "=========================================="
if kubectl top nodes &>/dev/null; then
    kubectl top nodes
    echo -e "${GREEN}✓ PASS: ノードメトリクスを取得できました${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL: ノードメトリクスを取得できません${NC}"
    FAILED=$((FAILED + 1))
fi

# テスト9: Podメトリクス取得
echo ""
echo "=========================================="
echo "[9/10] Podメトリクス取得テスト"
echo "=========================================="
if kubectl top pods -n kube-system &>/dev/null; then
    kubectl top pods -n kube-system | head -10
    echo -e "${GREEN}✓ PASS: Podメトリクスを取得できました${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL: Podメトリクスを取得できません${NC}"
    FAILED=$((FAILED + 1))
fi

# テスト10: Metrics Serverログ確認
echo ""
echo "=========================================="
echo "[10/10] Metrics Serverログ確認"
echo "=========================================="
echo "最新のログ（5行）:"
kubectl logs -n kube-system -l app.kubernetes.io/name=metrics-server --tail=5 2>/dev/null

ERROR_COUNT=$(kubectl logs -n kube-system -l app.kubernetes.io/name=metrics-server --tail=50 2>/dev/null | grep -ci "error" || echo "0")
if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ PASS: ログにエラーなし${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠ WARNING: ログに${ERROR_COUNT}件のエラーあり${NC}"
    PASSED=$((PASSED + 1))
fi

# 最終結果
echo ""
echo "=========================================="
echo "検証結果サマリー"
echo "=========================================="
echo "環境: ${ENV_NAME}"
echo "合格: ${PASSED}/10"
echo "不合格: ${FAILED}/10"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ すべてのテストに合格しました！${NC}"
    echo "=========================================="
    exit 0
else
    echo -e "${RED}✗ ${FAILED}件のテストが失敗しました${NC}"
    echo ""
    echo "トラブルシューティングが必要です:"
    echo "  1. ログ確認: kubectl logs -n kube-system -l app.kubernetes.io/name=metrics-server"
    echo "  2. Pod詳細: kubectl describe pod -n kube-system -l app.kubernetes.io/name=metrics-server"
    echo "  3. 再実行: ./enable-metrics-server.sh"
    echo "=========================================="
    exit 1
fi
