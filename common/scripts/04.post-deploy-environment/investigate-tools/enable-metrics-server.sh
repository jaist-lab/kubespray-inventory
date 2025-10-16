#!/bin/bash
# Metrics Server有効化スクリプト（修正版）

set -e

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ヘッダー表示
echo "=========================================="
echo "Metrics Server有効化スクリプト（修正版）"
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
echo "Kubeconfig: ${KUBECONFIG}"
echo ""

# 確認プロンプト
read -p "この環境でMetrics Serverを有効化しますか？ (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "キャンセルしました"
    exit 0
fi

# ステップ1: バックアップ
echo ""
echo "=========================================="
echo "[1/7] バックアップ作成"
echo "=========================================="
BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p ${BACKUP_DIR}
kubectl get deployment metrics-server -n kube-system -o yaml > ${BACKUP_DIR}/metrics-server-deployment.yaml 2>/dev/null || true
kubectl get deployment kubelet-csr-approver -n kube-system -o yaml > ${BACKUP_DIR}/kubelet-csr-approver-deployment.yaml 2>/dev/null || true
kubectl get csr -o yaml > ${BACKUP_DIR}/csr-list.yaml 2>/dev/null || true
echo -e "${GREEN}✓ バックアップ完了: ${BACKUP_DIR}/${NC}"

# ステップ2: ConfigMap適用
echo ""
echo "=========================================="
echo "[2/7] ConfigMap適用"
echo "=========================================="
if [ ! -f "${CONFIG_FILE}" ]; then
    echo -e "${RED}✗ エラー: ${CONFIG_FILE} が見つかりません${NC}"
    echo "先にConfigMapファイルを作成してください"
    exit 1
fi

kubectl apply -f ${CONFIG_FILE}
echo -e "${GREEN}✓ ConfigMap適用完了${NC}"

# ステップ3: kubelet-csr-approver再起動
echo ""
echo "=========================================="
echo "[3/7] kubelet-csr-approver再起動"
echo "=========================================="
kubectl rollout restart deployment kubelet-csr-approver -n kube-system
kubectl rollout status deployment kubelet-csr-approver -n kube-system --timeout=120s

echo ""
echo "起動確認（30秒待機）..."
sleep 30
kubectl get pods -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver
echo -e "${GREEN}✓ kubelet-csr-approver再起動完了${NC}"

# ステップ4: CSRクリーンアップ
echo ""
echo "=========================================="
echo "[4/7] CSRクリーンアップ"
echo "=========================================="
kubectl delete csr --all 2>/dev/null || true
echo -e "${GREEN}✓ CSRクリーンアップ完了${NC}"

# ステップ5: kubelet再起動
echo ""
echo "=========================================="
echo "[5/7] 全ノードkubelet再起動"
echo "=========================================="
for node in $NODE_IPS; do
    echo ""
    echo "=== Restarting kubelet on $node ==="
    ssh jaist-lab@$node "sudo systemctl restart kubelet" && \
        echo -e "${GREEN}✓ $node - 成功${NC}" || \
        echo -e "${RED}✗ $node - 失敗${NC}"
    sleep 2
done
echo -e "${GREEN}✓ 全ノードkubelet再起動完了${NC}"

# ステップ6: CSR自動承認待機
echo ""
echo "=========================================="
echo "[6/7] CSR自動承認待機"
echo "=========================================="
echo "新しいCSRの生成を待機中（30秒）..."
sleep 30

kubectl get csr
# 修正: カウント取得を安全に
CSR_COUNT=$(kubectl get csr --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "生成されたCSR数: ${CSR_COUNT}"

echo ""
echo "CSRの自動承認を待機中（60秒）..."
sleep 60

kubectl get csr
# 修正: カウント取得を安全に
APPROVED_COUNT=$(kubectl get csr 2>/dev/null | grep "Approved,Issued" | wc -l | tr -d ' ')
DENIED_COUNT=$(kubectl get csr 2>/dev/null | grep "Denied" | wc -l | tr -d ' ')
PENDING_COUNT=$(kubectl get csr 2>/dev/null | grep "Pending" | wc -l | tr -d ' ')

echo ""
echo "CSR状態サマリー:"
echo "  承認済み (Approved): ${APPROVED_COUNT}"
echo "  拒否 (Denied): ${DENIED_COUNT}"
echo "  保留 (Pending): ${PENDING_COUNT}"
echo "  合計: ${CSR_COUNT}"

# 修正: 数値比較を安全に実行
if [ "${CSR_COUNT}" -gt 0 ] 2>/dev/null; then
    if [ "${APPROVED_COUNT}" -eq "${CSR_COUNT}" ] 2>/dev/null; then
        echo -e "${GREEN}✓ すべてのCSRが自動承認されました${NC}"
    else
        echo -e "${YELLOW}⚠ 一部のCSRが承認されていません${NC}"
        
        # Pendingのみ手動承認を試行
        if [ "${PENDING_COUNT}" -gt 0 ] 2>/dev/null; then
            echo ""
            echo "Pending状態のCSRを手動承認します..."
            kubectl get csr -o name | grep -v "Approved" | xargs -r kubectl certificate approve 2>/dev/null || true
            sleep 10
            
            # 再カウント
            APPROVED_COUNT=$(kubectl get csr 2>/dev/null | grep "Approved,Issued" | wc -l | tr -d ' ')
            echo "手動承認後の承認済みCSR: ${APPROVED_COUNT} / ${CSR_COUNT}"
        fi
        
        # Deniedが多い場合は警告
        if [ "${DENIED_COUNT}" -gt 0 ] 2>/dev/null; then
            echo -e "${RED}✗ ${DENIED_COUNT}個のCSRが拒否(Denied)されています${NC}"
            echo ""
            echo "拒否の原因調査が必要です。次のセクションで詳細を確認します。"
        fi
    fi
else
    echo -e "${YELLOW}⚠ CSRが生成されていません${NC}"
fi

# 証明書確認
echo ""
echo "kubelet-server証明書確認:"
CERT_SUCCESS=0
CERT_TOTAL=0
for node in $NODE_IPS; do
    CERT_TOTAL=$((CERT_TOTAL + 1))
    if ssh jaist-lab@$node "sudo ls /var/lib/kubelet/pki/kubelet-server-current.pem" &>/dev/null; then
        echo -e "${GREEN}✓ $node - 証明書あり${NC}"
        CERT_SUCCESS=$((CERT_SUCCESS + 1))
    else
        echo -e "${RED}✗ $node - 証明書なし${NC}"
    fi
done

echo ""
echo "証明書生成結果: ${CERT_SUCCESS} / ${CERT_TOTAL} ノード"

# ステップ7: Metrics Server再起動
echo ""
echo "=========================================="
echo "[7/7] Metrics Server再起動"
echo "=========================================="

if [ "${CERT_SUCCESS}" -gt 0 ] 2>/dev/null; then
    echo "証明書が生成されたため、Metrics Serverを再起動します..."
    kubectl delete pod -n kube-system -l app.kubernetes.io/name=metrics-server
    echo ""
    echo "Metrics Server起動待機（60秒）..."
    sleep 60
    
    kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
    
    # Readiness確認
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=metrics-server -n kube-system --timeout=60s 2>/dev/null; then
        echo -e "${GREEN}✓ Metrics Server起動成功${NC}"
    else
        echo -e "${RED}✗ Metrics Server起動失敗${NC}"
        echo ""
        echo "ログを確認:"
        kubectl logs -n kube-system -l app.kubernetes.io/name=metrics-server --tail=30
    fi
else
    echo -e "${RED}✗ 証明書が生成されていないため、Metrics Serverをスキップします${NC}"
fi

# 最終動作確認
echo ""
echo "=========================================="
echo "最終動作確認"
echo "=========================================="

if [ "${CERT_SUCCESS}" -gt 0 ] 2>/dev/null; then
    echo ""
    echo "[1/3] ノードメトリクス取得テスト:"
    if kubectl top nodes 2>/dev/null; then
        echo -e "${GREEN}✓ ノードメトリクス取得成功${NC}"
    else
        echo -e "${RED}✗ ノードメトリクス取得失敗${NC}"
    fi
    
    echo ""
    echo "[2/3] Podメトリクス取得テスト:"
    if kubectl top pods -n kube-system 2>/dev/null | head -10; then
        echo -e "${GREEN}✓ Podメトリクス取得成功${NC}"
    else
        echo -e "${RED}✗ Podメトリクス取得失敗${NC}"
    fi
    
    echo ""
    echo "[3/3] APIサービス確認:"
    kubectl get apiservice v1beta1.metrics.k8s.io
    
    AVAILABLE=$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
    if [ "$AVAILABLE" == "True" ]; then
        echo -e "${GREEN}✓ Metrics Server APIが利用可能です${NC}"
    else
        echo -e "${RED}✗ Metrics Server APIが利用できません${NC}"
    fi
else
    echo -e "${YELLOW}証明書が生成されていないため、動作確認をスキップします${NC}"
fi

# サマリー
echo ""
echo "=========================================="
echo "処理完了サマリー"
echo "=========================================="
echo "環境: ${ENV_NAME}"
echo "kubelet-csr-approver: $(kubectl get pods -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver --no-headers 2>/dev/null | wc -l) Pod(s) Running"
echo "Metrics Server: $(kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo 'N/A')"
echo "CSR統計:"
echo "  - 承認済み: ${APPROVED_COUNT}"
echo "  - 拒否: ${DENIED_COUNT}"
echo "  - 保留: ${PENDING_COUNT}"
echo "  - 合計: ${CSR_COUNT}"
echo "証明書生成: ${CERT_SUCCESS} / ${CERT_TOTAL} ノード"
echo "バックアップ: ${BACKUP_DIR}/"
echo ""

if [ "${DENIED_COUNT}" -gt 0 ] 2>/dev/null; then
    echo -e "${RED}⚠ CSRが拒否されています - 原因調査が必要です${NC}"
    echo ""
    echo "次のステップ:"
    echo "  1. 原因調査スクリプトを実行: ./investigate-csr-denied.sh"
    echo "  2. kubelet-csr-approverログ確認: kubectl logs -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver"
elif [ "${CERT_SUCCESS}" -eq "${CERT_TOTAL}" ] 2>/dev/null; then
    echo -e "${GREEN}✓ Metrics Server有効化作業完了${NC}"
else
    echo -e "${YELLOW}⚠ 一部のノードで証明書生成に失敗しました${NC}"
    echo ""
    echo "次のステップ:"
    echo "  1. 原因調査スクリプトを実行: ./investigate-csr-denied.sh"
fi
echo "=========================================="