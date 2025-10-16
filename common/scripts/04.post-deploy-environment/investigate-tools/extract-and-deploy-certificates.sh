#!/bin/bash
# CSRから証明書を抽出してkubeletに配置

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

export KUBECONFIG=~/.kube/config-production

# 失敗した4ノードの情報
declare -A NODE_MAP
NODE_MAP["172.16.100.101"]="master01:csr-szq99"
NODE_MAP["172.16.100.102"]="master02:csr-twv2h"
NODE_MAP["172.16.100.112"]="node02:csr-j46pn"
NODE_MAP["172.16.100.113"]="node03:csr-8swrx"

echo "=========================================="
echo "証明書手動抽出・配置"
echo "=========================================="
echo ""

for node_ip in "${!NODE_MAP[@]}"; do
    IFS=':' read -r node_name csr_name <<< "${NODE_MAP[$node_ip]}"
    
    echo ""
    echo "=========================================="
    echo "処理: ${node_name} (${node_ip})"
    echo "CSR: ${csr_name}"
    echo "=========================================="
    
    # ステップ1: CSRから証明書を抽出
    echo "[1/5] 証明書データ抽出..."
    CERT_DATA=$(kubectl get csr ${csr_name} -o jsonpath='{.status.certificate}')
    
    if [ -z "$CERT_DATA" ]; then
        echo -e "${RED}✗ 証明書データなし - スキップ${NC}"
        continue
    fi
    
    echo "証明書データ長: ${#CERT_DATA}文字"
    
    # ステップ2: base64デコードしてローカルに保存
    echo ""
    echo "[2/5] 証明書デコード..."
    TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
    CERT_FILE="/tmp/kubelet-server-${node_name}-${TIMESTAMP}.pem"
    
    echo "$CERT_DATA" | base64 -d > ${CERT_FILE}
    
    # 証明書の検証
    if openssl x509 -in ${CERT_FILE} -noout -text &>/dev/null; then
        echo -e "${GREEN}✓ 証明書デコード成功${NC}"
        
        # 証明書の詳細表示
        echo "証明書情報:"
        openssl x509 -in ${CERT_FILE} -noout -subject -dates
    else
        echo -e "${RED}✗ 証明書が無効 - スキップ${NC}"
        rm -f ${CERT_FILE}
        continue
    fi
    
    # ステップ3: リモートノードにコピー
    echo ""
    echo "[3/5] リモートノードにコピー..."
    scp ${CERT_FILE} jaist-lab@${node_ip}:/tmp/
    
    # ステップ4: リモートノードで証明書を配置
    echo ""
    echo "[4/5] 証明書配置..."
    
    ssh jaist-lab@${node_ip} << EOF
        # rootに切り替えて作業
        sudo bash -c '
        # kubelet停止
        systemctl stop kubelet
        
        # 証明書ディレクトリ確認
        mkdir -p /var/lib/kubelet/pki
        
        # 証明書を配置
        REMOTE_CERT_FILE="/var/lib/kubelet/pki/kubelet-server-${TIMESTAMP}.pem"
        mv /tmp/$(basename ${CERT_FILE}) \${REMOTE_CERT_FILE}
        
        # シンボリックリンク作成
        ln -sf \${REMOTE_CERT_FILE} /var/lib/kubelet/pki/kubelet-server-current.pem
        
        # 権限設定
        chmod 600 /var/lib/kubelet/pki/kubelet-server-*.pem
        chown root:root /var/lib/kubelet/pki/kubelet-server-*.pem
        
        # kubelet起動
        systemctl start kubelet
        '
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 証明書配置成功${NC}"
    else
        echo -e "${RED}✗ 証明書配置失敗${NC}"
        continue
    fi
    
    # ステップ5: 検証
    echo ""
    echo "[5/5] 証明書確認（10秒待機）..."
    sleep 10
    
    if ssh jaist-lab@${node_ip} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo -e "${GREEN}✓ ${node_name} - 証明書配置確認成功${NC}"
        
        # 証明書の詳細
        echo "配置された証明書:"
        ssh jaist-lab@${node_ip} "sudo openssl x509 -in /var/lib/kubelet/pki/kubelet-server-current.pem -noout -subject -dates" 2>/dev/null
    else
        echo -e "${RED}✗ ${node_name} - 証明書が見つかりません${NC}"
    fi
    
    # ローカルの一時ファイル削除
    rm -f ${CERT_FILE}
    
    echo ""
done

echo ""
echo "=========================================="
echo "最終確認"
echo "=========================================="

ALL_NODES="172.16.100.101 172.16.100.102 172.16.100.103 172.16.100.111 172.16.100.112 172.16.100.113"
SUCCESS_COUNT=0
TOTAL_COUNT=0

for node in $ALL_NODES; do
    NODE_NAME=$(kubectl get nodes -o wide 2>/dev/null | grep ${node} | awk '{print $1}')
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    
    printf "%-20s " "${NODE_NAME}:"
    
    if ssh jaist-lab@${node} "sudo test -f /var/lib/kubelet/pki/kubelet-server-current.pem" 2>/dev/null; then
        echo -e "${GREEN}✓ 証明書あり${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}✗ 証明書なし${NC}"
    fi
done

echo ""
echo "=========================================="
echo "結果: ${SUCCESS_COUNT} / ${TOTAL_COUNT} ノード成功"
echo "=========================================="

if [ ${SUCCESS_COUNT} -eq ${TOTAL_COUNT} ]; then
    echo -e "${GREEN}✓ すべてのノードに証明書が配置されました！${NC}"
    echo ""
    echo "次のステップ:"
    echo "  1. Metrics Server再起動: kubectl delete pod -n kube-system -l app.kubernetes.io/name=metrics-server"
    echo "  2. 60秒待機後、動作確認: kubectl top nodes"
else
    echo -e "${YELLOW}⚠ 一部のノードで証明書配置に失敗しました${NC}"
fi

echo "=========================================="
