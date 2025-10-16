#!/bin/bash
# CSR Denied原因調査スクリプト

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "CSR Denied 原因調査スクリプト"
echo "=========================================="
echo ""

# 環境選択
echo "調査する環境を選択してください:"
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
echo -e "${BLUE}環境: ${ENV_NAME}${NC}"
echo ""

# ログファイル
LOG_FILE="csr-investigation-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a ${LOG_FILE})
exec 2>&1

echo "調査結果は ${LOG_FILE} に保存されます"
echo ""

# ========================================
# 調査1: CSRの状態詳細
# ========================================
echo "=========================================="
echo "[1/8] CSRの状態詳細"
echo "=========================================="

CSR_COUNT=$(kubectl get csr --no-headers 2>/dev/null | wc -l | tr -d ' ')
APPROVED_COUNT=$(kubectl get csr 2>/dev/null | grep "Approved,Issued" | wc -l | tr -d ' ')
DENIED_COUNT=$(kubectl get csr 2>/dev/null | grep "Denied" | wc -l | tr -d ' ')
PENDING_COUNT=$(kubectl get csr 2>/dev/null | grep "Pending" | wc -l | tr -d ' ')

echo "CSR統計:"
echo "  合計: ${CSR_COUNT}"
echo "  承認済み (Approved): ${APPROVED_COUNT}"
echo "  拒否 (Denied): ${DENIED_COUNT}"
echo "  保留 (Pending): ${PENDING_COUNT}"
echo ""

if [ "${CSR_COUNT}" -eq 0 ]; then
    echo -e "${YELLOW}⚠ CSRが存在しません${NC}"
    echo ""
    echo "CSRが生成されない原因:"
    echo "  1. kubeletが起動していない"
    echo "  2. kubeletの設定でserverTLSBootstrapが無効"
    echo "  3. ネットワーク問題"
    exit 0
fi

# Deniedの詳細を表示（最大5件）
if [ "${DENIED_COUNT}" -gt 0 ]; then
    echo -e "${RED}拒否されたCSRの詳細（最大5件）:${NC}"
    echo ""
    
    DENIED_CSRS=$(kubectl get csr 2>/dev/null | grep Denied | head -5 | awk '{print $1}')
    for csr in $DENIED_CSRS; do
        echo "--- CSR: $csr ---"
        kubectl get csr $csr -o yaml | grep -A 20 "status:" || true
        echo ""
    done
fi

# ========================================
# 調査2: kubelet-csr-approverの状態
# ========================================
echo ""
echo "=========================================="
echo "[2/8] kubelet-csr-approverの状態"
echo "=========================================="

kubectl get deployment -n kube-system kubelet-csr-approver
echo ""
kubectl get pods -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver

APPROVER_READY=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -c "True" || echo "0")
APPROVER_EXPECTED=$(kubectl get deployment -n kube-system kubelet-csr-approver -o jsonpath='{.spec.replicas}')

if [ "${APPROVER_READY}" -ne "${APPROVER_EXPECTED}" ]; then
    echo -e "${RED}✗ kubelet-csr-approverが正常に起動していません${NC}"
    echo ""
    echo "Pod詳細:"
    kubectl describe pods -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver | tail -50
else
    echo -e "${GREEN}✓ kubelet-csr-approverは正常に起動しています${NC}"
fi

# ========================================
# 調査3: kubelet-csr-approverのログ
# ========================================
echo ""
echo "=========================================="
echo "[3/8] kubelet-csr-approverのログ（最新100行）"
echo "=========================================="

kubectl logs -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver --tail=100 2>/dev/null | tail -50

echo ""
echo "エラーメッセージの検索:"
ERROR_COUNT=$(kubectl logs -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver --tail=200 2>/dev/null | grep -i "error\|denied\|fail" | wc -l)
echo "エラー関連行数: ${ERROR_COUNT}"

if [ "${ERROR_COUNT}" -gt 0 ]; then
    echo ""
    echo "エラーメッセージ（最新10件）:"
    kubectl logs -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver --tail=200 2>/dev/null | grep -i "error\|denied\|fail" | tail -10
fi

# ========================================
# 調査4: ConfigMapの内容確認
# ========================================
echo ""
echo "=========================================="
echo "[4/8] ConfigMapの内容確認"
echo "=========================================="

if kubectl get cm -n kube-system kubelet-csr-approver &>/dev/null; then
    echo -e "${GREEN}✓ ConfigMapが存在します${NC}"
    echo ""
    kubectl get cm -n kube-system kubelet-csr-approver -o yaml
    
    echo ""
    echo "重要な設定の確認:"
    if kubectl get cm -n kube-system kubelet-csr-approver -o yaml | grep -q "bypassDNSResolution: true"; then
        echo -e "${GREEN}✓ bypassDNSResolution: true${NC}"
    else
        echo -e "${RED}✗ bypassDNSResolution: true が設定されていません${NC}"
    fi
    
    if kubectl get cm -n kube-system kubelet-csr-approver -o yaml | grep -q "bypassHostnameCheck: true"; then
        echo -e "${GREEN}✓ bypassHostnameCheck: true${NC}"
    else
        echo -e "${RED}✗ bypassHostnameCheck: true が設定されていません${NC}"
    fi
else
    echo -e "${RED}✗ ConfigMapが存在しません${NC}"
    echo ""
    echo "これが問題の主な原因です。ConfigMapを作成する必要があります。"
fi

# ========================================
# 調査5: 特定のCSRの詳細分析（Denied）
# ========================================
echo ""
echo "=========================================="
echo "[5/8] Denied CSRの詳細分析"
echo "=========================================="

if [ "${DENIED_COUNT}" -gt 0 ]; then
    # 最新のDenied CSRを1つ詳しく調査
    SAMPLE_CSR=$(kubectl get csr 2>/dev/null | grep Denied | head -1 | awk '{print $1}')
    
    if [ -n "$SAMPLE_CSR" ]; then
        echo "サンプルCSR: ${SAMPLE_CSR}"
        echo ""
        
        echo "--- 基本情報 ---"
        kubectl get csr ${SAMPLE_CSR}
        echo ""
        
        echo "--- リクエスタ ---"
        kubectl get csr ${SAMPLE_CSR} -o jsonpath='{.spec.username}'
        echo ""
        echo ""
        
        echo "--- 拒否理由 ---"
        kubectl get csr ${SAMPLE_CSR} -o jsonpath='{.status.conditions[?(@.type=="Denied")].message}'
        echo ""
        echo ""
        
        echo "--- Subject Alternative Names (SAN) ---"
        kubectl get csr ${SAMPLE_CSR} -o jsonpath='{.spec.request}' | base64 -d | openssl req -noout -text 2>/dev/null | grep -A 10 "Subject Alternative Name" || echo "SANの取得に失敗"
    fi
else
    echo "Deniedのcsrがありません（これは良い兆候です）"
fi

# ========================================
# 調査6: kubeletの設定確認（1ノードのみ）
# ========================================
echo ""
echo "=========================================="
echo "[6/8] kubeletの設定確認（サンプルノード）"
echo "=========================================="

# 最初のワーカーノードで確認
SAMPLE_NODE=$(echo $NODE_IPS | awk '{print $4}')  # 4番目のノード（最初のワーカー）
echo "サンプルノード: ${SAMPLE_NODE}"
echo ""

echo "--- serverTLSBootstrap設定 ---"
ssh jaist-lab@${SAMPLE_NODE} "sudo cat /var/lib/kubelet/config.yaml | grep -E 'serverTLSBootstrap|rotateCertificates'" 2>/dev/null || echo "設定の取得に失敗"

echo ""
echo "--- kubeletログ（CSR関連） ---"
ssh jaist-lab@${SAMPLE_NODE} "sudo journalctl -u kubelet --since '10 minutes ago' | grep -i 'csr\|certificate' | tail -20" 2>/dev/null || echo "ログの取得に失敗"

# ========================================
# 調査7: ノードとCSRの対応関係
# ========================================
echo ""
echo "=========================================="
echo "[7/8] ノードとCSRの対応関係"
echo "=========================================="

echo "各ノードに対するCSRの状態:"
echo ""

for node in $NODE_IPS; do
    # ノード名を取得
    NODE_NAME=$(kubectl get nodes -o wide | grep ${node} | awk '{print $1}')
    
    if [ -n "$NODE_NAME" ]; then
        echo "--- ${NODE_NAME} (${node}) ---"
        
        # このノードに関するCSRをカウント
        NODE_APPROVED=$(kubectl get csr 2>/dev/null | grep "system:node:${NODE_NAME}" | grep -c "Approved" || echo "0")
        NODE_DENIED=$(kubectl get csr 2>/dev/null | grep "system:node:${NODE_NAME}" | grep -c "Denied" || echo "0")
        NODE_PENDING=$(kubectl get csr 2>/dev/null | grep "system:node:${NODE_NAME}" | grep -c "Pending" || echo "0")
        
        echo "  Approved: ${NODE_APPROVED}"
        echo "  Denied: ${NODE_DENIED}"
        echo "  Pending: ${NODE_PENDING}"
        
        # 証明書の存在確認
        if ssh jaist-lab@${node} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
            echo -e "  証明書: ${GREEN}あり${NC}"
        else
            echo -e "  証明書: ${RED}なし${NC}"
        fi
        
        echo ""
    fi
done

# ========================================
# 調査8: 推奨される対処法
# ========================================
echo ""
echo "=========================================="
echo "[8/8] 問題の診断と推奨対処法"
echo "=========================================="
echo ""

# 診断ロジック
ISSUE_FOUND=0

# 診断1: ConfigMap
if ! kubectl get cm -n kube-system kubelet-csr-approver &>/dev/null; then
    echo -e "${RED}[問題1] ConfigMapが存在しません${NC}"
    echo "対処法: kubelet-csr-approver用のConfigMapを作成する"
    echo "  kubectl apply -f kubelet-csr-approver-config-${ENV_NAME}.yaml"
    echo ""
    ISSUE_FOUND=1
elif ! kubectl get cm -n kube-system kubelet-csr-approver -o yaml | grep -q "bypassDNSResolution: true"; then
    echo -e "${RED}[問題2] ConfigMapにbypassDNSResolutionが設定されていません${NC}"
    echo "対処法: ConfigMapを修正してDNS検証をバイパスする"
    echo ""
    ISSUE_FOUND=1
fi

# 診断2: kubelet-csr-approverの状態
if [ "${APPROVER_READY}" -eq 0 ]; then
    echo -e "${RED}[問題3] kubelet-csr-approverが起動していません${NC}"
    echo "対処法: Deploymentを再起動する"
    echo "  kubectl rollout restart deployment kubelet-csr-approver -n kube-system"
    echo ""
    ISSUE_FOUND=1
fi

# 診断3: CSRが大量にDenied
if [ "${DENIED_COUNT}" -gt 10 ]; then
    echo -e "${RED}[問題4] 大量のCSRが拒否されています (${DENIED_COUNT}件)${NC}"
    echo "対処法:"
    echo "  1. kubelet-csr-approverを停止"
    echo "  2. 既存CSRをすべて削除"
    echo "  3. ConfigMapを修正"
    echo "  4. kubelet-csr-approverを再起動"
    echo "  5. 全ノードのkubeletを再起動"
    echo ""
    ISSUE_FOUND=1
fi

# 診断4: kubeletログにエラー
echo "kubeletログからエラーを検索中..."
KUBELET_ERROR=0
for node in $NODE_IPS; do
    if ssh jaist-lab@${node} "sudo journalctl -u kubelet --since '5 minutes ago' | grep -i 'error.*csr\|error.*certificate'" 2>/dev/null | head -1; then
        KUBELET_ERROR=1
    fi
done

if [ $KUBELET_ERROR -eq 1 ]; then
    echo -e "${YELLOW}[注意] kubeletログにCSR/証明書関連のエラーがあります${NC}"
    echo "対処法: 個別ノードのkubeletログを詳しく確認する"
    echo ""
    ISSUE_FOUND=1
fi

# 総合診断
echo ""
echo "=========================================="
if [ $ISSUE_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ 明確な問題は検出されませんでした${NC}"
    echo ""
    echo "CSRが拒否される原因として考えられること:"
    echo "  1. DNS解決の問題（最も可能性が高い）"
    echo "  2. ホスト名の不一致"
    echo "  3. IPアドレスの検証失敗"
    echo "  4. kubelet-csr-approverのバグまたは設定ミス"
else
    echo -e "${YELLOW}⚠ 上記の問題が検出されました${NC}"
fi
echo "=========================================="

echo ""
echo "=========================================="
echo "次のステップ"
echo "=========================================="
echo ""
echo "1. ConfigMapが正しく設定されていない場合:"
echo "   ./create-relaxed-configmap.sh"
echo ""
echo "2. 既存のCSRをクリーンアップして再試行:"
echo "   ./fix-csr-with-manual-approval.sh"
echo ""
echo "3. このログファイルを保存:"
echo "   ${LOG_FILE}"
echo ""
echo "=========================================="

echo ""
echo -e "${GREEN}調査完了${NC}"
echo "詳細は ${LOG_FILE} を参照してください"
