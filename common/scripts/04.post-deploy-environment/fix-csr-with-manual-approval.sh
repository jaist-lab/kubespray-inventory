#!/bin/bash
# CSR手動承認による修復スクリプト

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "CSR手動承認による修復スクリプト"
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
echo "このスクリプトは以下を実行します:"
echo "  1. kubelet-csr-approverを停止"
echo "  2. 既存のすべてのCSRを削除"
echo "  3. 全ノードを1つずつkubelet再起動"
echo "  4. 各ノードのCSRを手動承認"
echo "  5. 証明書生成を確認"
echo ""
read -p "続行しますか？ (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "キャンセルしました"
    exit 0
fi

# ステップ1: kubelet-csr-approverを停止
echo ""
echo "=========================================="
echo "[1/5] kubelet-csr-approverを停止"
echo "=========================================="

echo "kubelet-csr-approverを停止中..."
kubectl scale deployment kubelet-csr-approver -n kube-system --replicas=0

echo "停止確認（10秒待機）..."
sleep 10

APPROVER_PODS=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver --no-headers 2>/dev/null | wc -l)
if [ "${APPROVER_PODS}" -eq 0 ]; then
    echo -e "${GREEN}✓ kubelet-csr-approver停止完了${NC}"
else
    echo -e "${YELLOW}⚠ まだPodが存在します（Terminating中）${NC}"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=kubelet-csr-approver
fi

# ステップ2: 既存CSRを削除
echo ""
echo "=========================================="
echo "[2/5] 既存CSRをすべて削除"
echo "=========================================="

CSR_COUNT=$(kubectl get csr --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "削除対象CSR数: ${CSR_COUNT}"

if [ "${CSR_COUNT}" -gt 0 ]; then
    kubectl delete csr --all
    echo -e "${GREEN}✓ CSR削除完了${NC}"
else
    echo "削除対象のCSRなし"
fi

sleep 5

# ステップ3-5: 1ノードずつ処理
echo ""
echo "=========================================="
echo "[3-5/5] ノードごとの処理"
echo "=========================================="
echo ""
echo "各ノードで以下を実行します:"
echo "  1. kubelet再起動"
echo "  2. CSR生成待機"
echo "  3. CSR手動承認"
echo "  4. 証明書生成確認"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for node in $NODE_IPS; do
    echo ""
    echo "=========================================="
    echo "処理中: ${node}"
    echo "=========================================="
    
    # ノード名を取得
    NODE_NAME=$(kubectl get nodes -o wide | grep ${node} | awk '{print $1}')
    
    if [ -z "$NODE_NAME" ]; then
        echo -e "${RED}✗ ノード名を取得できません: ${node}${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    echo "ノード名: ${NODE_NAME}"
    
    # 3.1: kubelet再起動
    echo ""
    echo "[1/4] kubelet再起動..."
    if ssh jaist-lab@${node} "sudo systemctl restart kubelet" 2>/dev/null; then
        echo -e "${GREEN}✓ kubelet再起動成功${NC}"
    else
        echo -e "${RED}✗ kubelet再起動失敗${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    # 3.2: CSR生成待機
    echo ""
    echo "[2/4] CSR生成待機（15秒）..."
    sleep 15
    
    # CSRを探す
    NEW_CSR=$(kubectl get csr 2>/dev/null | grep "system:node:${NODE_NAME}" | grep -E "Pending|Denied" | tail -1 | awk '{print $1}')
    
    if [ -z "$NEW_CSR" ]; then
        echo -e "${RED}✗ CSRが生成されませんでした${NC}"
        echo ""
        echo "デバッグ情報:"
        echo "全CSR:"
        kubectl get csr | tail -5
        echo ""
        echo "kubeletログ:"
        ssh jaist-lab@${node} "sudo journalctl -u kubelet --since '30 seconds ago' | grep -i csr | tail -5" 2>/dev/null || echo "ログ取得失敗"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    echo "CSR発見: ${NEW_CSR}"
    
    # CSRの状態を確認
    CSR_STATUS=$(kubectl get csr ${NEW_CSR} -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "None")
    echo "CSR状態: ${CSR_STATUS}"
    
    # 3.3: CSR手動承認
    echo ""
    echo "[3/4] CSR手動承認..."
    if kubectl certificate approve ${NEW_CSR} 2>/dev/null; then
        echo -e "${GREEN}✓ CSR承認成功${NC}"
        
        # 承認確認
        sleep 3
        APPROVAL_STATUS=$(kubectl get csr ${NEW_CSR} -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
        echo "承認後の状態: ${APPROVAL_STATUS}"
    else
        echo -e "${RED}✗ CSR承認失敗${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    # 3.4: 証明書生成確認
    echo ""
    echo "[4/4] 証明書生成確認（10秒待機）..."
    sleep 10
    
    if ssh jaist-lab@${node} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo -e "${GREEN}✓ 証明書生成成功${NC}"
        
        # 証明書の詳細
        echo "証明書情報:"
        ssh jaist-lab@${node} "sudo ls -lh /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null || echo "詳細取得失敗"
        
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}✗ 証明書生成失敗${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    echo ""
    echo "このノードの処理完了"
    sleep 2
done

# 最終結果
echo ""
echo "=========================================="
echo "処理完了サマリー"
echo "=========================================="
echo "環境: ${ENV_NAME}"
echo "成功: ${SUCCESS_COUNT} ノード"
echo "失敗: ${FAIL_COUNT} ノード"
echo ""

# 全体の証明書確認
echo "全ノードの証明書状態:"
for node in $NODE_IPS; do
    NODE_NAME=$(kubectl get nodes -o wide | grep ${node} | awk '{print $1}')
    printf "%-20s " "${NODE_NAME} (${node}):"
    
    if ssh jaist-lab@${node} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo -e "${GREEN}✓ 証明書あり${NC}"
    else
        echo -e "${RED}✗ 証明書なし${NC}"
    fi
done

echo ""
echo "=========================================="

NODE_COUNT=$(echo $NODE_IPS | wc -w)

if [ "${SUCCESS_COUNT}" -eq "${NODE_COUNT}" ]; then
    echo -e "${GREEN}✓ すべてのノードで証明書生成に成功しました！${NC}"
    echo ""
    echo "次のステップ:"
    echo "  1. Metrics Serverを再起動:"
    echo "     kubectl delete pod -n kube-system -l app.kubernetes.io/name=metrics-server"
    echo ""
    echo "  2. 60秒待機後、動作確認:"
    echo "     kubectl top nodes"
    echo "     kubectl top pods -A"
    echo ""
    echo "  3. （オプション）kubelet-csr-approverを再度有効化:"
    echo "     kubectl scale deployment kubelet-csr-approver -n kube-system --replicas=2"
elif [ "${SUCCESS_COUNT}" -gt 0 ]; then
    echo -e "${YELLOW}⚠ 一部のノードで証明書生成に成功しました${NC}"
    echo ""
    echo "失敗したノードの調査:"
    echo "  ./investigate-csr-denied.sh"
else
    echo -e "${RED}✗ すべてのノードで証明書生成に失敗しました${NC}"
    echo ""
    echo "根本的な問題がある可能性があります。"
    echo "原因調査スクリプトを実行してください:"
    echo "  ./investigate-csr-denied.sh"
fi

echo "=========================================="
