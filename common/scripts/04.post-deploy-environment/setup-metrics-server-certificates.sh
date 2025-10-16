#!/bin/bash
# Metrics Server証明書セットアップ統合スクリプト
# ------------------------------------------------------------------------------
# このスクリプトは、Kubernetesクラスタの各ノードに対して
# Metrics Server用のkubelet証明書を生成し、配置するためのものです。
# 以下の手順を自動化しています:
# 
#  1. ConfigMap適用（kubelet-csr-approver設定）
#  2. kubelet-csr-approverを停止
#  3. 既存のすべてのCSRを削除
#  4. 全ノードを1つずつkubelet再起動        
#  5. 各ノードのCSRを手動承認
#  6. 証明書生成を確認
#  7. Metrics Server再起動  
# ------------------------------------------------------------------------------
## エラー時の再実行について
# このスクリプトは**冪等性（べきとうせい）** を考慮した設計になっています。
# 途中でエラーが発生した場合でも、再度実行することで
# 失敗したノードのみを再処理できます。
# ただし、ノードの状態によっては手動での介入が必要になる場合があります。
# その場合は、スクリプトの出力メッセージに従ってください。
## **注意**: 冪等性を保つために、ノードのkubeletサービスが停止している場合は
# 手動で再起動してください。
# 例: `sudo systemctl restart kubelet`  
# また、kubelet-csr-approverが停止している場合は
# 手動で再度有効化してください。
# 例: `kubectl scale deployment kubelet-csr-approver -n kube-system --replicas=2`   
# ------------------------------------------------------------------------------
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Metrics Server証明書セットアップ"
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
echo -e "${BLUE}環境: ${ENV_NAME}${NC}"
echo -e "${BLUE}ConfigMap: ${CONFIG_FILE}${NC}"
echo ""

# ConfigMapファイルの存在確認
if [ ! -f "${CONFIG_FILE}" ]; then
    echo -e "${RED}✗ エラー: ${CONFIG_FILE} が見つかりません${NC}"
    echo ""
    echo "ConfigMapファイルを作成してください:"
    echo "  cd ~/kubernetes/metrics-server-setup"
    echo "  ls -l kubelet-csr-approver-config-*.yaml"
    exit 1
fi

echo "このスクリプトは以下を実行します:"
echo "  1. ConfigMap適用（kubelet-csr-approver設定）"
echo "  2. kubelet-csr-approverを停止"
echo "  3. 既存のすべてのCSRを削除"
echo "  4. 全ノードを1つずつkubelet再起動"
echo "  5. 各ノードのCSRを手動承認"
echo "  6. 証明書生成を確認"
echo "  7. Metrics Server再起動"
echo ""
read -p "続行しますか？ (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "キャンセルしました"
    exit 0
fi

# バックアップディレクトリ作成
BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p ${BACKUP_DIR}
echo ""
echo "バックアップディレクトリ: ${BACKUP_DIR}"

# ステップ0: ConfigMap適用
echo ""
echo "=========================================="
echo "[0/7] ConfigMap適用"
echo "=========================================="

# 既存ConfigMapをバックアップ
kubectl get cm -n kube-system kubelet-csr-approver -o yaml > ${BACKUP_DIR}/kubelet-csr-approver-configmap.yaml 2>/dev/null || echo "既存ConfigMapなし"

echo "ConfigMapを適用中..."
kubectl apply -f ${CONFIG_FILE}

echo ""
echo "適用されたConfigMap内容:"
kubectl get cm -n kube-system kubelet-csr-approver -o yaml | grep -A 20 "config.yaml:"

echo ""
echo -e "${GREEN}✓ ConfigMap適用完了${NC}"

# ステップ1: kubelet-csr-approverを停止
echo ""
echo "=========================================="
echo "[1/7] kubelet-csr-approverを停止"
echo "=========================================="

# 既存deploymentをバックアップ
kubectl get deployment -n kube-system kubelet-csr-approver -o yaml > ${BACKUP_DIR}/kubelet-csr-approver-deployment.yaml 2>/dev/null || echo "既存Deploymentなし"

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
    echo "追加で10秒待機..."
    sleep 10
fi

# ステップ2: 既存CSRを削除
echo ""
echo "=========================================="
echo "[2/7] 既存CSRをすべて削除"
echo "=========================================="

# 既存CSRをバックアップ
kubectl get csr -o yaml > ${BACKUP_DIR}/csr-list.yaml 2>/dev/null || true

CSR_COUNT=$(kubectl get csr --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "削除対象CSR数: ${CSR_COUNT}"

if [ "${CSR_COUNT}" -gt 0 ]; then
    kubectl delete csr --all
    echo -e "${GREEN}✓ CSR削除完了${NC}"
else
    echo "削除対象のCSRなし"
fi

sleep 5

# ステップ3-6: 1ノードずつ処理
echo ""
echo "=========================================="
echo "[3-6/7] ノードごとの証明書生成"
echo "=========================================="
echo ""
echo "各ノードで以下を実行します:"
echo "  1. kubelet再起動"
echo "  2. CSR生成待機（30秒）"
echo "  3. CSR手動承認"
echo "  4. 証明書生成確認（10秒待機）"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
declare -a FAILED_NODES

for node in $NODE_IPS; do
    echo ""
    echo "=========================================="
    echo "処理中: ${node}"
    echo "=========================================="
    
    # ノード名を取得
    NODE_NAME=$(kubectl get nodes -o wide 2>/dev/null | grep ${node} | awk '{print $1}')
    
    if [ -z "$NODE_NAME" ]; then
        echo -e "${RED}✗ ノード名を取得できません: ${node}${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_NODES+=("${node}")
        continue
    fi
    
    echo "ノード名: ${NODE_NAME}"
    
    # 既存の証明書を確認
    echo ""
    echo "既存証明書確認:"
    if ssh jaist-lab@${node} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo "  既存証明書あり - 削除します"
        ssh jaist-lab@${node} "sudo rm -f /var/lib/kubelet/pki/kubelet-server-*.pem" 2>/dev/null || true
    else
        echo "  既存証明書なし"
    fi
    
    # 3.1: kubelet再起動
    echo ""
    echo "[1/4] kubelet再起動..."
    if ssh jaist-lab@${node} "sudo systemctl restart kubelet" 2>/dev/null; then
        echo -e "${GREEN}✓ kubelet再起動成功${NC}"
    else
        echo -e "${RED}✗ kubelet再起動失敗${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_NODES+=("${node}")
        continue
    fi
    
    # 3.2: CSR生成待機
    echo ""
    echo "[2/4] CSR生成待機（30秒）..."
    sleep 30
    
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
        ssh jaist-lab@${node} "sudo journalctl -u kubelet --since '30 seconds ago' | grep -i csr | tail -10" 2>/dev/null || echo "ログ取得失敗"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_NODES+=("${node}")
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
        FAILED_NODES+=("${node}")
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
        ssh jaist-lab@${node} "sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-server-current.pem -noout -subject -dates" 2>/dev/null || echo "詳細取得失敗"
        
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}✗ 証明書生成失敗${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_NODES+=("${node}")
    fi
    
    echo ""
    echo "このノードの処理完了"
    sleep 2
done

# ステップ7: Metrics Server再起動
echo ""
echo "=========================================="
echo "[7/7] Metrics Server再起動"
echo "=========================================="

NODE_COUNT=$(echo $NODE_IPS | wc -w)

echo ""
echo "証明書生成結果: ${SUCCESS_COUNT} / ${NODE_COUNT} ノード"
echo ""

if [ "${SUCCESS_COUNT}" -gt 0 ]; then
    echo "証明書が生成されたノードがあるため、Metrics Serverを再起動します..."
    
    kubectl delete pod -n kube-system -l app.kubernetes.io/name=metrics-server 2>/dev/null || echo "Metrics Server Podなし"
    
    echo ""
    echo "Metrics Server起動待機（60秒）..."
    sleep 60
    
    echo ""
    echo "Metrics Server Pod状態:"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
    
    # Readiness確認
    echo ""
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=metrics-server -n kube-system --timeout=60s 2>/dev/null; then
        echo -e "${GREEN}✓ Metrics Server起動成功${NC}"
    else
        echo -e "${YELLOW}⚠ Metrics Server起動タイムアウト${NC}"
        echo ""
        echo "ログ確認:"
        kubectl logs -n kube-system -l app.kubernetes.io/name=metrics-server --tail=20 2>/dev/null || echo "ログ取得失敗"
    fi
    
    # 動作確認
    echo ""
    echo "=========================================="
    echo "動作確認"
    echo "=========================================="
    
    echo ""
    echo "[1/2] ノードメトリクス取得テスト:"
    if kubectl top nodes 2>/dev/null; then
        echo -e "${GREEN}✓ ノードメトリクス取得成功${NC}"
    else
        echo -e "${YELLOW}⚠ ノードメトリクス取得失敗（証明書未生成ノードの影響）${NC}"
    fi
    
    echo ""
    echo "[2/2] APIサービス確認:"
    kubectl get apiservice v1beta1.metrics.k8s.io
    
    AVAILABLE=$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
    if [ "$AVAILABLE" == "True" ]; then
        echo -e "${GREEN}✓ Metrics Server APIが利用可能です${NC}"
    else
        echo -e "${YELLOW}⚠ Metrics Server APIが完全には利用できません${NC}"
    fi
else
    echo -e "${RED}✗ 証明書が生成されなかったため、Metrics Server再起動をスキップします${NC}"
fi

# 最終結果
echo ""
echo "=========================================="
echo "処理完了サマリー"
echo "=========================================="
echo "環境: ${ENV_NAME}"
echo "成功: ${SUCCESS_COUNT} ノード"
echo "失敗: ${FAIL_COUNT} ノード"
echo "バックアップ: ${BACKUP_DIR}/"
echo ""

# 全体の証明書確認
echo "全ノードの証明書状態:"
for node in $NODE_IPS; do
    NODE_NAME=$(kubectl get nodes -o wide 2>/dev/null | grep ${node} | awk '{print $1}')
    printf "%-20s " "${NODE_NAME} (${node}):"
    
    if ssh jaist-lab@${node} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo -e "${GREEN}✓ 証明書あり${NC}"
    else
        echo -e "${RED}✗ 証明書なし${NC}"
    fi
done

echo ""
echo "=========================================="

if [ "${SUCCESS_COUNT}" -eq "${NODE_COUNT}" ]; then
    echo -e "${GREEN}✓ すべてのノードで証明書生成に成功しました！${NC}"
    echo ""
    echo "次のステップ:"
    echo "  1. 動作確認:"
    echo "     kubectl top nodes"
    echo "     kubectl top pods -n kube-system"
    echo ""
    echo "  2. （オプション）kubelet-csr-approverを再度有効化:"
    echo "     kubectl scale deployment kubelet-csr-approver -n kube-system --replicas=2"
    echo ""
elif [ "${SUCCESS_COUNT}" -gt 0 ]; then
    echo -e "${YELLOW}⚠ 一部のノードで証明書生成に成功しました${NC}"
    echo ""
    echo "失敗したノード:"
    for failed_node in "${FAILED_NODES[@]}"; do
        NODE_NAME=$(kubectl get nodes -o wide 2>/dev/null | grep ${failed_node} | awk '{print $1}')
        echo "  - ${NODE_NAME} (${failed_node})"
    done
    echo ""
    echo "次のステップ:"
    echo "  1. このスクリプトを再実行（失敗ノードのみ処理）"
    echo "  2. または手動で証明書を抽出・配置"
    echo ""
    echo "再実行コマンド:"
    echo "  ./setup-metrics-server-certificates.sh"
    echo ""
else
    echo -e "${RED}✗ すべてのノードで証明書生成に失敗しました${NC}"
    echo ""
    echo "根本的な問題がある可能性があります。"
    echo ""
    echo "次のステップ:"
    echo "  1. 原因調査スクリプトを実行:"
    echo "     ./investigate-csr-denied.sh"
    echo ""
    echo "  2. kubelet設定を確認:"
    echo "     ssh jaist-lab@<node> 'sudo cat /var/lib/kubelet/config.yaml | grep -E \"rotate|tls\"'"
    echo ""
    echo "  3. このスクリプトを再実行:"
    echo "     ./setup-metrics-server-certificates.sh"
fi

echo "=========================================="
