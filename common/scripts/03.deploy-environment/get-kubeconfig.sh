#!/bin/bash
# Kubeconfig取得スクリプト（修正版）

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
    echo "=========================================="
    echo "環境: ${ENV_NAME}"
    echo "Master IP: ${MASTER_IP}"
    echo "Kubeconfig: ~/.kube/${CONFIG_NAME}"
    echo "=========================================="
    
    # Kubeconfigディレクトリ作成
    mkdir -p ~/.kube
    
    # 一時ファイル名
    local TEMP_FILE="/tmp/admin.conf.${MASTER_IP}"
    
    echo "[1/4] リモートホストでファイルをコピー中..."
    # リモートホストでファイルをコピーして権限変更
    ssh jaist-lab@${MASTER_IP} "sudo cp /etc/kubernetes/admin.conf ${TEMP_FILE} && \
                                  sudo chown jaist-lab:jaist-lab ${TEMP_FILE} && \
                                  sudo chmod 644 ${TEMP_FILE}"
    
    echo "[2/4] ローカルにコピー中..."
    # ローカルにコピー
    scp jaist-lab@${MASTER_IP}:${TEMP_FILE} ~/.kube/${CONFIG_NAME}
    
    echo "[3/4] リモート側の一時ファイル削除中..."
    # リモート側の一時ファイル削除
    ssh jaist-lab@${MASTER_IP} "rm -f ${TEMP_FILE}"
    
    echo "[4/4] ローカルの権限設定中..."
    # Kubeconfig権限設定
    chmod 600 ~/.kube/${CONFIG_NAME}
    
    # APIサーバーアドレスを修正（macOS/Linux対応）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS用
        sed -i '' "s|https://127.0.0.1:6443|https://${MASTER_IP}:6443|g" ~/.kube/${CONFIG_NAME}
    else
        # Linux用
        sed -i "s|https://127.0.0.1:6443|https://${MASTER_IP}:6443|g" ~/.kube/${CONFIG_NAME}
    fi
    
    # サーバーアドレス確認
    local API_SERVER=$(grep "server:" ~/.kube/${CONFIG_NAME} | awk '{print $2}')
    echo ""
    echo "✓ Kubeconfig取得完了"
    echo "  API Server: ${API_SERVER}"
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
        echo ""
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
