#!/bin/bash
# 失敗ノードの詳細デバッグ

export KUBECONFIG=~/.kube/config-production
FAILED_NODES="172.16.100.101 172.16.100.102 172.16.100.112 172.16.100.113"

echo "=========================================="
echo "失敗ノードの詳細調査"
echo "=========================================="
echo ""

for node in $FAILED_NODES; do
    NODE_NAME=$(kubectl get nodes -o wide | grep ${node} | awk '{print $1}')
    
    echo "=========================================="
    echo "ノード: ${NODE_NAME} (${node})"
    echo "=========================================="
    
    # 最新のCSRを取得
    LATEST_CSR=$(kubectl get csr | grep "system:node:${NODE_NAME}" | tail -1 | awk '{print $1}')
    
    if [ -n "$LATEST_CSR" ]; then
        echo ""
        echo "--- 最新CSR: ${LATEST_CSR} ---"
        kubectl get csr ${LATEST_CSR} -o yaml
        
        echo ""
        echo "--- CSRの詳細ステータス ---"
        CSR_STATUS=$(kubectl get csr ${LATEST_CSR} -o jsonpath='{.status}')
        echo "$CSR_STATUS" | python3 -m json.tool 2>/dev/null || echo "$CSR_STATUS"
        
        echo ""
        echo "--- 証明書が発行されているか ---"
        CERT=$(kubectl get csr ${LATEST_CSR} -o jsonpath='{.status.certificate}')
        if [ -n "$CERT" ]; then
            echo "✓ 証明書データあり（長さ: ${#CERT}文字）"
            echo ""
            echo "証明書の内容:"
            echo "$CERT" | base64 -d | openssl x509 -noout -text | head -30
        else
            echo "✗ 証明書データなし - これが問題です"
        fi
    else
        echo "✗ CSRが見つかりません"
    fi
    
    echo ""
    echo "--- kubeletログ（最新20行） ---"
    ssh jaist-lab@${node} "sudo journalctl -u kubelet --since '2 minutes ago' | grep -i 'certificate\|csr' | tail -20" 2>/dev/null || echo "ログ取得失敗"
    
    echo ""
    echo "=========================================="
    echo ""
done
