#!/bin/bash
# Kubeconfig取得スクリプト（macOS対応版）

set -e

echo "=========================================="
echo "Kubeconfig switch"
echo "=========================================="

# 環境選択
echo "環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
read -p "選択 (1/2/3): " ENV_CHOICE

get_kubeconfig() {
    local ENV_NAME=$1
    local MASTER_IP=$2
    local CONFIG_NAME=$3
    
    echo ""
    echo "環境: ${ENV_NAME}"
    echo "Master IP: ${MASTER_IP}"
    echo "Kubeconfig: ~/.kube/${CONFIG_NAME}"
    
    # ローカルにコピー
    cp ~/.kube/${CONFIG_NAME} ~/.kube/config
    
    
    # サーバーアドレス確認
    local API_SERVER=$(grep "server:" ~/.kube/${CONFIG_NAME} | awk '{print $2}')
    echo "  API Server: ${API_SERVER}"
    
    # 接続テスト
    echo "  接続テスト中..."
    if KUBECONFIG=~/.kube/${CONFIG_NAME} kubectl cluster-info &>/dev/null; then
        echo "  ✓ 接続成功"
    else
        echo "  ⚠ 接続テスト失敗（クラスタ起動を確認してください）"
    fi
    
    echo "  ✓ Kubeconfig取得完了"
}

case $ENV_CHOICE in
    1)
        get_kubeconfig "Production" "172.16.100.101" "config-production"
        ;;
    2)
        get_kubeconfig "Development" "172.16.100.121" "config-development"
        ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

