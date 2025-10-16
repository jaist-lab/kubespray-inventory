#!/bin/bash
# dev-master03のserverTLSBootstrap設定追加と修復

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TARGET_NODE="172.16.100.123"
NODE_NAME="dev-master03"
export KUBECONFIG=~/.kube/config-development

echo "=========================================="
echo "dev-master03 証明書問題修復"
echo "=========================================="
echo ""

# ステップ1: 現在の設定確認
echo "[1/6] 現在の設定確認"
echo ""

echo "--- kubelet config.yaml ---"
ssh jaist-lab@${TARGET_NODE} "sudo cat /var/lib/kubelet/config.yaml | grep -E 'rotate|bootstrap'" || echo "設定なし"

echo ""
read -p "serverTLSBootstrapを追加しますか？ (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "キャンセルしました"
    exit 0
fi

# ステップ2: バックアップ
echo ""
echo "[2/6] 設定ファイルバックアップ"
ssh jaist-lab@${TARGET_NODE} "sudo cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.backup-$(date +%Y%m%d-%H%M%S)"
echo -e "${GREEN}✓ バックアップ完了${NC}"

# ステップ3: serverTLSBootstrap追加
echo ""
echo "[3/6] serverTLSBootstrap追加"
ssh jaist-lab@${TARGET_NODE} "sudo sed -i '/rotateCertificates:/a serverTLSBootstrap: true' /var/lib/kubelet/config.yaml"

# 設定確認
echo ""
echo "追加後の設定:"
ssh jaist-lab@${TARGET_NODE} "sudo cat /var/lib/kubelet/config.yaml | grep -A 1 'rotateCertificates:'"

echo ""
echo -e "${GREEN}✓ serverTLSBootstrap追加完了${NC}"

# ステップ4: 既存証明書削除
echo ""
echo "[4/6] 既存証明書削除"
ssh jaist-lab@${TARGET_NODE} "sudo rm -f /var/lib/kubelet/pki/kubelet-server-*.pem"
echo -e "${GREEN}✓ 証明書削除完了${NC}"

# ステップ5: 既存CSR削除
echo ""
echo "[5/6] 既存CSR削除"
kubectl get csr | grep ${NODE_NAME} | awk '{print $1}' | xargs -r kubectl delete csr 2>/dev/null || true
echo -e "${GREEN}✓ CSR削除完了${NC}"

# ステップ6: kubelet再起動とCSR承認
echo ""
echo "[6/6] kubelet再起動とCSR生成確認"
echo ""

ssh jaist-lab@${TARGET_NODE} "sudo systemctl restart kubelet"
echo "kubelet再起動完了"

echo ""
echo "CSR生成待機（30秒）..."
sleep 30

# CSR確認
echo ""
echo "CSR状態:"
kubectl get csr | grep ${NODE_NAME} || echo "CSRなし"

NEW_CSR=$(kubectl get csr 2>/dev/null | grep ${NODE_NAME} | grep -E "Pending|Denied" | tail -1 | awk '{print $1}')

if [ -n "$NEW_CSR" ]; then
    echo ""
    echo -e "${GREEN}✓ CSRが生成されました: ${NEW_CSR}${NC}"
    
    echo ""
    read -p "CSRを承認しますか？ (yes/no): " APPROVE_CONFIRM
    
    if [ "$APPROVE_CONFIRM" == "yes" ]; then
        kubectl certificate approve ${NEW_CSR}
        echo -e "${GREEN}✓ CSR承認完了${NC}"
        
        echo ""
        echo "証明書生成待機（10秒）..."
        sleep 10
        
        if ssh jaist-lab@${TARGET_NODE} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
            echo -e "${GREEN}✓ 証明書生成成功${NC}"
            
            echo ""
            echo "証明書情報:"
            ssh jaist-lab@${TARGET_NODE} "sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-server-current.pem -noout -subject -dates"
            
            echo ""
            echo "=========================================="
            echo "修復完了"
            echo "=========================================="
            echo ""
            echo "次のステップ:"
            echo "  1. Metrics Server再起動:"
            echo "     kubectl delete pod -n kube-system -l app.kubernetes.io/name=metrics-server"
            echo ""
            echo "  2. 60秒待機後、動作確認:"
            echo "     kubectl top nodes"
        else
            echo -e "${RED}✗ 証明書生成失敗${NC}"
            echo ""
            echo "kubeletログを確認:"
            ssh jaist-lab@${TARGET_NODE} "sudo journalctl -u kubelet --since '2 minutes ago' | grep -i 'certificate\|csr\|bootstrap' | tail -20"
        fi
    fi
else
    echo -e "${RED}✗ CSRが生成されませんでした${NC}"
    echo ""
    echo "kubeletログを確認:"
    ssh jaist-lab@${TARGET_NODE} "sudo journalctl -u kubelet --since '1 minute ago' | grep -i 'rotate-server-certificates\|bootstrap' | tail -10"
    echo ""
    echo "起動フラグを確認:"
    ssh jaist-lab@${TARGET_NODE} "ps aux | grep [k]ubelet | grep -o 'rotate-server-certificates=[^[:space:]]*'"
fi

echo ""
echo "=========================================="
