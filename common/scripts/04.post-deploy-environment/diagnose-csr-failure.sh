#!/bin/bash
# CSR生成失敗の詳細診断スクリプト

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "CSR生成失敗 詳細診断"
echo "=========================================="
echo ""

# 環境選択
echo "対象環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo "  3) Sandbox"
read -p "選択 (1 or 2 or 3): " ENV_CHOICE

case $ENV_CHOICE in
    1)
        ENV_NAME="production"
        export KUBECONFIG=~/.kube/config-production
        TARGET_NODE_IP="172.16.100.101"
        ;;
    2)
        ENV_NAME="development"
        export KUBECONFIG=~/.kube/config-development
        TARGET_NODE_IP="172.16.100.123"  # dev-master03
        ;;
    3)
        ENV_NAME="sandbox"
        export KUBECONFIG=~/.kube/config-sandbox
        TARGET_NODE_IP="172.16.100.133"  # sandbox-master03
        ;;
    *)
        echo -e "${RED}✗ 無効な選択です${NC}"
        exit 1
        ;;
esac

echo ""
echo "診断対象ノード: ${TARGET_NODE_IP}"
echo ""

NODE_NAME=$(kubectl get nodes -o wide 2>/dev/null | grep ${TARGET_NODE_IP} | awk '{print $1}')

if [ -z "$NODE_NAME" ]; then
    echo -e "${RED}✗ ノード名を取得できません${NC}"
    exit 1
fi

echo "ノード名: ${NODE_NAME}"
echo ""

LOG_FILE="csr-diagnostic-${NODE_NAME}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a ${LOG_FILE})
exec 2>&1

echo "診断結果は ${LOG_FILE} に保存されます"
echo ""

# ============================================
# 診断1: kubelet設定確認
# ============================================
echo "=========================================="
echo "[1/8] kubelet設定確認"
echo "=========================================="
echo ""

echo "--- /var/lib/kubelet/config.yaml ---"
ssh jaist-lab@${TARGET_NODE_IP} "sudo cat /var/lib/kubelet/config.yaml" 2>/dev/null

echo ""
echo "--- 重要な設定項目 ---"
echo -n "rotateCertificates: "
ssh jaist-lab@${TARGET_NODE_IP} "sudo grep 'rotateCertificates:' /var/lib/kubelet/config.yaml" 2>/dev/null || echo "設定なし"

echo -n "serverTLSBootstrap: "
ssh jaist-lab@${TARGET_NODE_IP} "sudo grep 'serverTLSBootstrap:' /var/lib/kubelet/config.yaml" 2>/dev/null || echo -e "${RED}設定なし（これが問題の可能性）${NC}"

# ============================================
# 診断2: kubelet起動オプション確認
# ============================================
echo ""
echo "=========================================="
echo "[2/8] kubelet起動オプション確認"
echo "=========================================="
echo ""

echo "--- systemd unit file ---"
ssh jaist-lab@${TARGET_NODE_IP} "sudo systemctl cat kubelet | grep -A 10 'ExecStart='" 2>/dev/null

echo ""
echo "--- 実行中のkubeletプロセス ---"
ssh jaist-lab@${TARGET_NODE_IP} "ps aux | grep [k]ubelet" 2>/dev/null

# ============================================
# 診断3: kubelet証明書ディレクトリ確認
# ============================================
echo ""
echo "=========================================="
echo "[3/8] 証明書ディレクトリ確認"
echo "=========================================="
echo ""

ssh jaist-lab@${TARGET_NODE_IP} "sudo ls -la /var/lib/kubelet/pki/" 2>/dev/null || echo "ディレクトリなし"

# ============================================
# 診断4: kubeletログ詳細
# ============================================
echo ""
echo "=========================================="
echo "[4/8] kubeletログ詳細（最新50行）"
echo "=========================================="
echo ""

ssh jaist-lab@${TARGET_NODE_IP} "sudo journalctl -u kubelet --since '5 minutes ago' -n 50 --no-pager" 2>/dev/null

echo ""
echo "--- CSR関連ログ ---"
ssh jaist-lab@${TARGET_NODE_IP} "sudo journalctl -u kubelet --since '5 minutes ago' | grep -i 'csr\|certificate\|tls'" 2>/dev/null | tail -20

# ============================================
# 診断5: API Server接続確認
# ============================================
echo ""
echo "=========================================="
echo "[5/8] API Server接続確認"
echo "=========================================="
echo ""

echo "--- kubeconfigファイル ---"
ssh jaist-lab@${TARGET_NODE_IP} "sudo cat /etc/kubernetes/kubelet.conf | grep -E 'server:|certificate-authority'" 2>/dev/null

echo ""
echo "--- API Server疎通確認 ---"
ssh jaist-lab@${TARGET_NODE_IP} "sudo curl -k https://172.16.100.123:6443/healthz" 2>/dev/null || echo "接続失敗"

# ============================================
# 診断6: 既存CSR確認
# ============================================
echo ""
echo "=========================================="
echo "[6/8] 既存CSR確認"
echo "=========================================="
echo ""

echo "--- このノードに関連するCSR ---"
kubectl get csr | grep ${NODE_NAME} || echo "CSRなし"

echo ""
echo "--- 全CSR ---"
kubectl get csr

# ============================================
# 診断7: kubelet再起動テスト
# ============================================
echo ""
echo "=========================================="
echo "[7/8] kubelet再起動テスト"
echo "=========================================="
echo ""

read -p "kubeletを再起動してCSR生成をテストしますか？ (yes/no): " TEST_RESTART

if [ "$TEST_RESTART" == "yes" ]; then
    echo ""
    echo "既存証明書を削除中..."
    ssh jaist-lab@${TARGET_NODE_IP} "sudo rm -f /var/lib/kubelet/pki/kubelet-server-*.pem" 2>/dev/null || true
    
    echo "kubelet再起動中..."
    ssh jaist-lab@${TARGET_NODE_IP} "sudo systemctl restart kubelet"
    
    echo ""
    echo "CSR生成待機（45秒）..."
    for i in {1..9}; do
        sleep 5
        echo "  ${i}0秒経過..."
        
        NEW_CSR=$(kubectl get csr 2>/dev/null | grep ${NODE_NAME} | tail -1)
        if [ -n "$NEW_CSR" ]; then
            echo ""
            echo -e "${GREEN}✓ CSRが生成されました！${NC}"
            echo "$NEW_CSR"
            break
        fi
    done
    
    if [ -z "$NEW_CSR" ]; then
        echo ""
        echo -e "${RED}✗ 45秒経過してもCSRが生成されませんでした${NC}"
    fi
    
    echo ""
    echo "--- kubeletログ（再起動後） ---"
    ssh jaist-lab@${TARGET_NODE_IP} "sudo journalctl -u kubelet --since '1 minute ago' | grep -i 'csr\|certificate\|bootstrap'" 2>/dev/null | tail -30
fi

# ============================================
# 診断8: 推奨対処法
# ============================================
echo ""
echo "=========================================="
echo "[8/8] 診断結果と推奨対処法"
echo "=========================================="
echo ""

# serverTLSBootstrap設定確認
HAS_SERVER_TLS_BOOTSTRAP=$(ssh jaist-lab@${TARGET_NODE_IP} "sudo grep -c 'serverTLSBootstrap: true' /var/lib/kubelet/config.yaml" 2>/dev/null || echo "0")

if [ "$HAS_SERVER_TLS_BOOTSTRAP" -eq 0 ]; then
    echo -e "${RED}[問題] serverTLSBootstrap が設定されていません${NC}"
    echo ""
    echo "これがCSR生成されない主な原因です。"
    echo ""
    echo "対処法:"
    echo "  1. kubelet設定ファイルに serverTLSBootstrap: true を追加"
    echo "  2. kubelet再起動"
    echo ""
    echo "実行コマンド:"
    echo "  ssh jaist-lab@${TARGET_NODE_IP} \"sudo sed -i '/rotateCertificates:/a serverTLSBootstrap: true' /var/lib/kubelet/config.yaml\""
    echo "  ssh jaist-lab@${TARGET_NODE_IP} \"sudo systemctl restart kubelet\""
    echo ""
else
    echo -e "${GREEN}[正常] serverTLSBootstrap: true が設定されています${NC}"
    echo ""
    echo "他の原因を調査する必要があります:"
    echo "  - API Server接続問題"
    echo "  - kubelet起動オプションの問題"
    echo "  - 証明書ディレクトリの権限問題"
fi

echo ""
echo "=========================================="
echo "診断完了"
echo "=========================================="
echo ""
echo "ログファイル: ${LOG_FILE}"
echo ""
