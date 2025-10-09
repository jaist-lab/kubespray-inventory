#!/bin/bash
# Kubeconfig取得スクリプト

set -e

echo "=========================================="
echo "Kubeconfig取得"
echo "=========================================="

# 環境選択
echo "取得する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo "  3) 両方"
read -p "選択 (1/2/3): " ENV_CHOICE

get_kubeconfig() {
    local ENV_NAME=$1
    local MASTER_IP=$2
    local CONFIG_NAME=$3
    
    echo ""
    echo "環境: ${ENV_NAME}"
    echo "Master IP: ${MASTER_IP}"
    echo "Kubeconfig: ~/.kube/${CONFIG_NAME}"
    
    # Kubeconfig取得
    mkdir -p ~/.kube
    scp jaist-lab@${MASTER_IP}:/etc/kubernetes/admin.conf ~/.kube/${CONFIG_NAME}
    
    # 権限設定
    chmod 600 ~/.kube/${CONFIG_NAME}
    
    echo "✓ Kubeconfig取得完了"
}

case $ENV_CHOICE in
    1)
        get_kubeconfig "Production" "172.16.100.101" "config-production"
        ;;
    2)
        get_kubeconfig "Development" "172.16.100.121" "config-development"
        ;;
    3)
        get_kubeconfig "Production" "172.16.100.101" "config-production"
        get_kubeconfig "Development" "172.16.100.121" "config-development"
        ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "使用方法"
echo "=========================================="
echo "Production環境:"
echo "  export KUBECONFIG=~/.kube/config-production"
echo "  kubectl get nodes"
echo ""
echo "Development環境:"
echo "  export KUBECONFIG=~/.kube/config-development"
echo "  kubectl get nodes"
echo "=========================================="
