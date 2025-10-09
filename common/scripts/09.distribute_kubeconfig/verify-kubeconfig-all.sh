#!/bin/bash
# 全ノードのkubeconfig配布状態を確認

set -e

echo "=========================================="
echo "Kubeconfig配布確認"
echo "=========================================="
echo ""

# 環境選択
echo "確認する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo "  3) 両方"
read -p "選択 (1/2/3): " ENV_CHOICE

verify_nodes() {
    local ENV_NAME=$1
    shift
    local NODES=("$@")
    
    echo ""
    echo "=== ${ENV_NAME}環境 ==="
    echo ""
    
    local SUCCESS=0
    local FAILED=0
    
    for node in "${NODES[@]}"; do
        printf "%-20s " "${node}:"
        
        # kubeconfigファイルの存在確認
        if ssh -o ConnectTimeout=5 jaist-lab@${node} "test -f ~/.kube/config-${ENV_NAME}" 2>/dev/null; then
            # kubectl接続テスト
            if ssh -o ConnectTimeout=5 jaist-lab@${node} "export KUBECONFIG=~/.kube/config-${ENV_NAME}; kubectl get nodes &>/dev/null" 2>/dev/null; then
                echo "✓ OK (kubeconfig有効・接続成功)"
                SUCCESS=$((SUCCESS + 1))
            else
                echo "⚠ WARNING (kubeconfigあり・接続失敗)"
                FAILED=$((FAILED + 1))
            fi
        else
            echo "✗ FAILED (kubeconfigなし)"
            FAILED=$((FAILED + 1))
        fi
    done
    
    echo ""
    echo "結果: 成功 ${SUCCESS}/${#NODES[@]}, 失敗 ${FAILED}/${#NODES[@]}"
}

case $ENV_CHOICE in
    1)
        PROD_NODES=(
            "172.16.100.101" "172.16.100.102" "172.16.100.103"
            "172.16.100.111" "172.16.100.112" "172.16.100.113"
        )
        verify_nodes "production" "${PROD_NODES[@]}"
        ;;
    2)
        DEV_NODES=(
            "172.16.100.121" "172.16.100.122" "172.16.100.123"
            "172.16.100.131" "172.16.100.132" "172.16.100.133"
        )
        verify_nodes "development" "${DEV_NODES[@]}"
        ;;
    3)
        PROD_NODES=(
            "172.16.100.101" "172.16.100.102" "172.16.100.103"
            "172.16.100.111" "172.16.100.112" "172.16.100.113"
        )
        verify_nodes "production" "${PROD_NODES[@]}"
        
        DEV_NODES=(
            "172.16.100.121" "172.16.100.122" "172.16.100.123"
            "172.16.100.131" "172.16.100.132" "172.16.100.133"
        )
        verify_nodes "development" "${DEV_NODES[@]}"
        ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
