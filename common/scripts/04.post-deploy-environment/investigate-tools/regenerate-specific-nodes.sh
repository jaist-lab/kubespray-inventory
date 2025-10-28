#!/bin/bash
# 特定ノードのみ証明書再生成スクリプト
# ------------------------------------------------------------------------------
# このスクリプトは、Kubernetesクラスタの特定ノードに対
# してkubelet証明書を再生成し、配置するためのものです。
# 既に証明書が存在するノードはスキップし、失敗したノードのみ処理します。
# 以下の手順を自動化しています:
# 
#  1. ConfigMap適用（kubelet-csr-approver設定）
#  2. kubelet-csr-approverを停止
#  3. 対象ノードのCSR削除
#  4. 対象ノードの証明書再生成
#  5. Metrics Server再起動
# 
# 選択オプション
# |入力    |動作                          |使用例                           |
# |-------|------------------------------|--------------------------------|
# |番号指定|指定した番号のノードのみ処理       |2 3 → dev-master02, dev-master03|
# |all    |すべてのノードを再生成            |all → 全6ノード                  |
# |auto   |メトリクス取得失敗ノードのみ自動検出|auto → 問題のあるノードのみ         |
#
# 注意: このスクリプトは、kubelet-csr-approverを停止します。
# 再起動は行いませんので、必要に応じて手動で再度有効化してください。
# 例: `kubectl scale deployment kubelet-csr-approver -n kube-system --replicas=2`

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo "特定ノード証明書再生成"
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
        ALL_NODE_IPS="172.16.100.101 172.16.100.102 172.16.100.103 172.16.100.111 172.16.100.112 172.16.100.113"
        ;;
    2)
        ENV_NAME="development"
        export KUBECONFIG=~/.kube/config-development
        CONFIG_FILE="kubelet-csr-approver-config-development.yaml"
        ALL_NODE_IPS="172.16.100.121 172.16.100.122 172.16.100.123 172.16.100.131 172.16.100.132 172.16.100.133"
        ;;
    *)
        echo -e "${RED}✗ 無効な選択です${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}環境: ${ENV_NAME}${NC}"
echo ""

# 全ノードの証明書状態を表示
echo "=========================================="
echo "現在の証明書状態"
echo "=========================================="
echo ""

declare -a NODE_LIST
INDEX=1

for node in $ALL_NODE_IPS; do
    NODE_NAME=$(kubectl get nodes -o wide 2>/dev/null | grep ${node} | awk '{print $1}')
    
    if [ -z "$NODE_NAME" ]; then
        continue
    fi
    
    NODE_LIST+=("${node}:${NODE_NAME}")
    
    printf "[%d] %-20s " "$INDEX" "${NODE_NAME} (${node})"
    
    if ssh jaist-lab@${node} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        EXPIRY=$(ssh jaist-lab@${node} "sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-server-current.pem -noout -enddate 2>/dev/null | cut -d= -f2")
        
        # Metrics取得状態確認
        METRICS=$(kubectl top node ${NODE_NAME} 2>/dev/null | tail -1 | awk '{print $2}')
        
        if [[ "$METRICS" == "<unknown>" ]] || [ -z "$METRICS" ]; then
            echo -e "${YELLOW}⚠ 証明書あり（有効期限: ${EXPIRY}）- メトリクス取得失敗${NC}"
        else
            echo -e "${GREEN}✓ 証明書あり（有効期限: ${EXPIRY}）- メトリクス正常${NC}"
        fi
    else
        echo -e "${RED}✗ 証明書なし${NC}"
    fi
    
    INDEX=$((INDEX + 1))
done

echo ""
echo "=========================================="
echo "再生成するノードを選択"
echo "=========================================="
echo ""
echo "再生成するノード番号をスペース区切りで入力してください"
echo "（例: 2 3  または  all  または  問題のあるノードのみの場合は auto）"
echo ""
read -p "選択: " SELECTION

# 選択されたノードを処理
declare -a TARGET_NODES

if [ "$SELECTION" == "all" ]; then
    # すべてのノード
    TARGET_NODES=("${NODE_LIST[@]}")
    echo ""
    echo -e "${YELLOW}⚠ すべてのノードを再生成します${NC}"
elif [ "$SELECTION" == "auto" ]; then
    # メトリクス取得失敗ノードのみ
    echo ""
    echo "メトリクス取得失敗ノードを自動検出中..."
    
    INDEX=1
    for node in $ALL_NODE_IPS; do
        NODE_NAME=$(kubectl get nodes -o wide 2>/dev/null | grep ${node} | awk '{print $1}')
        
        if [ -z "$NODE_NAME" ]; then
            continue
        fi
        
        METRICS=$(kubectl top node ${NODE_NAME} 2>/dev/null | tail -1 | awk '{print $2}')
        
        if [[ "$METRICS" == "<unknown>" ]] || [ -z "$METRICS" ]; then
            TARGET_NODES+=("${node}:${NODE_NAME}")
            echo "  - ${NODE_NAME} (${node})"
        fi
        
        INDEX=$((INDEX + 1))
    done
    
    if [ ${#TARGET_NODES[@]} -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ メトリクス取得失敗のノードはありません${NC}"
        exit 0
    fi
else
    # 指定された番号のノード
    for num in $SELECTION; do
        if [ $num -ge 1 ] && [ $num -le ${#NODE_LIST[@]} ]; then
            INDEX=$((num - 1))
            TARGET_NODES+=("${NODE_LIST[$INDEX]}")
        else
            echo -e "${RED}✗ 無効な番号: $num${NC}"
            exit 1
        fi
    done
fi

echo ""
echo "=========================================="
echo "再生成対象ノード確認"
echo "=========================================="
echo ""

for node_info in "${TARGET_NODES[@]}"; do
    IFS=':' read -r node_ip node_name <<< "$node_info"
    echo "  - ${node_name} (${node_ip})"
done

echo ""
read -p "これらのノードの証明書を再生成しますか？ (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "キャンセルしました"
    exit 0
fi

# バックアップディレクトリ作成
BACKUP_DIR="backup-regenerate-$(date +%Y%m%d-%H%M%S)"
mkdir -p ${BACKUP_DIR}
echo ""
echo "バックアップディレクトリ: ${BACKUP_DIR}"

# ConfigMap適用
echo ""
echo "=========================================="
echo "[1/5] ConfigMap適用"
echo "=========================================="

kubectl get cm -n kube-system kubelet-csr-approver -o yaml > ${BACKUP_DIR}/kubelet-csr-approver-configmap.yaml 2>/dev/null || true
kubectl apply -f ${CONFIG_FILE}
echo -e "${GREEN}✓ ConfigMap適用完了${NC}"

# kubelet-csr-approverを停止
echo ""
echo "=========================================="
echo "[2/5] kubelet-csr-approverを停止"
echo "=========================================="

kubectl get deployment -n kube-system kubelet-csr-approver -o yaml > ${BACKUP_DIR}/kubelet-csr-approver-deployment.yaml 2>/dev/null || true
kubectl scale deployment kubelet-csr-approver -n kube-system --replicas=0

echo "停止確認（10秒待機）..."
sleep 10
echo -e "${GREEN}✓ kubelet-csr-approver停止完了${NC}"

# 対象ノードのCSRを削除
echo ""
echo "=========================================="
echo "[3/5] 対象ノードのCSR削除"
echo "=========================================="

kubectl get csr -o yaml > ${BACKUP_DIR}/csr-list.yaml 2>/dev/null || true

for node_info in "${TARGET_NODES[@]}"; do
    IFS=':' read -r node_ip node_name <<< "$node_info"
    echo "  ${node_name}: CSR削除中..."
    
    kubectl get csr 2>/dev/null | grep "system:node:${node_name}" | awk '{print $1}' | xargs -r kubectl delete csr 2>/dev/null || true
done

echo -e "${GREEN}✓ CSR削除完了${NC}"
sleep 3

# 対象ノードの証明書再生成
echo ""
echo "=========================================="
echo "[4/5] 証明書再生成"
echo "=========================================="
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for node_info in "${TARGET_NODES[@]}"; do
    IFS=':' read -r node node_name <<< "$node_info"
    
    echo ""
    echo "=========================================="
    echo "処理中: ${node_name} (${node})"
    echo "=========================================="
    
    # 既存証明書削除
    echo ""
    echo "[1/5] 既存証明書削除..."
    ssh jaist-lab@${node} "sudo rm -f /var/lib/kubelet/pki/kubelet-server-*.pem" 2>/dev/null || true
    echo "✓ 削除完了"
    
    # kubelet再起動
    echo ""
    echo "[2/5] kubelet再起動..."
    if ssh jaist-lab@${node} "sudo systemctl restart kubelet" 2>/dev/null; then
        echo -e "${GREEN}✓ kubelet再起動成功${NC}"
    else
        echo -e "${RED}✗ kubelet再起動失敗${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    # CSR生成待機
    echo ""
    echo "[3/5] CSR生成待機（30秒）..."
    sleep 30
    
    # CSRを探す
    NEW_CSR=$(kubectl get csr 2>/dev/null | grep "system:node:${node_name}" | grep -E "Pending|Denied" | tail -1 | awk '{print $1}')
    
    if [ -z "$NEW_CSR" ]; then
        echo -e "${RED}✗ CSRが生成されませんでした${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    echo "CSR発見: ${NEW_CSR}"
    
    # CSR手動承認
    echo ""
    echo "[4/5] CSR手動承認..."
    if kubectl certificate approve ${NEW_CSR} 2>/dev/null; then
        echo -e "${GREEN}✓ CSR承認成功${NC}"
        sleep 3
    else
        echo -e "${RED}✗ CSR承認失敗${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    # 証明書生成確認
    echo ""
    echo "[5/5] 証明書生成確認（10秒待機）..."
    sleep 10
    
    if ssh jaist-lab@${node} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo -e "${GREEN}✓ 証明書生成成功${NC}"
        
        # 証明書の詳細
        echo "証明書情報:"
        ssh jaist-lab@${node} "sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-server-current.pem -noout -subject -dates" 2>/dev/null
        
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}✗ 証明書生成失敗${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    echo ""
    sleep 2
done

# Metrics Server再起動
echo ""
echo "=========================================="
echo "[5/5] Metrics Server再起動"
echo "=========================================="

if [ "${SUCCESS_COUNT}" -gt 0 ]; then
    kubectl delete pod -n kube-system -l app.kubernetes.io/name=metrics-server 2>/dev/null || true
    
    echo ""
    echo "起動待機（60秒）..."
    sleep 60
    
    kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server
    
    # Readiness確認
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=metrics-server -n kube-system --timeout=60s 2>/dev/null; then
        echo -e "${GREEN}✓ Metrics Server起動成功${NC}"
    else
        echo -e "${YELLOW}⚠ Metrics Server起動タイムアウト${NC}"
    fi
fi

# 最終結果
echo ""
echo "=========================================="
echo "処理完了サマリー"
echo "=========================================="
echo "環境: ${ENV_NAME}"
echo "対象ノード数: ${#TARGET_NODES[@]}"
echo "成功: ${SUCCESS_COUNT}"
echo "失敗: ${FAIL_COUNT}"
echo ""

# 動作確認
if [ "${SUCCESS_COUNT}" -gt 0 ]; then
    echo "=========================================="
    echo "動作確認"
    echo "=========================================="
    echo ""
    
    echo "メトリクス取得テスト:"
    kubectl top nodes
    
    echo ""
    echo "再生成したノードの状態:"
    for node_info in "${TARGET_NODES[@]}"; do
        IFS=':' read -r node_ip node_name <<< "$node_info"
        METRICS=$(kubectl top node ${node_name} 2>/dev/null | tail -1)
        
        if echo "$METRICS" | grep -q "<unknown>"; then
            echo -e "  ${RED}✗ ${node_name} - メトリクス取得失敗${NC}"
        else
            echo -e "  ${GREEN}✓ ${node_name} - ${METRICS}${NC}"
        fi
    done
fi

echo ""
echo "=========================================="

if [ "${SUCCESS_COUNT}" -eq "${#TARGET_NODES[@]}" ]; then
    echo -e "${GREEN}✓ すべての対象ノードで証明書再生成に成功しました${NC}"
elif [ "${SUCCESS_COUNT}" -gt 0 ]; then
    echo -e "${YELLOW}⚠ 一部のノードで証明書再生成に失敗しました${NC}"
    echo ""
    echo "このスクリプトを再実行して、失敗したノードのみ再処理できます"
else
    echo -e "${RED}✗ すべてのノードで証明書再生成に失敗しました${NC}"
fi

echo "=========================================="
