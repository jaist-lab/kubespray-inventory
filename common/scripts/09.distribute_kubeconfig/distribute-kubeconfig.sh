#!/bin/bash
# 全ノードにkubeconfigを配布するスクリプト

set -e

echo "=========================================="
echo "Kubeconfig配布スクリプト"
echo "=========================================="
echo ""

# 環境選択
echo "配布する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo "  3) 両方"
read -p "選択 (1/2/3): " ENV_CHOICE

distribute_kubeconfig() {
    local ENV_NAME=$1
    local MASTER_IP=$2
    shift 2
    local NODES=("$@")
    
    echo ""
    echo "=========================================="
    echo "${ENV_NAME}環境 kubeconfig配布"
    echo "=========================================="
    echo "Master: ${MASTER_IP}"
    echo "配布先ノード数: ${#NODES[@]}"
    echo ""
    
    # Masterノードから kubeconfig を取得
    echo "[1/3] Masterノードからkubeconfigを取得..."
    local TEMP_FILE="/tmp/admin.conf.${MASTER_IP}"
    
    ssh jaist-lab@${MASTER_IP} "sudo cp /etc/kubernetes/admin.conf ${TEMP_FILE} && \
                                  sudo chown jaist-lab:jaist-lab ${TEMP_FILE} && \
                                  sudo chmod 644 ${TEMP_FILE}"
    
    scp jaist-lab@${MASTER_IP}:${TEMP_FILE} /tmp/kubeconfig-${ENV_NAME}.tmp
    ssh jaist-lab@${MASTER_IP} "rm -f ${TEMP_FILE}"
    
    # APIサーバーアドレスを修正
    sed -i.bak "s|https://127.0.0.1:6443|https://${MASTER_IP}:6443|g" /tmp/kubeconfig-${ENV_NAME}.tmp
    
    echo "✓ kubeconfig取得完了"
    echo ""
    
    # 各ノードに配布
    echo "[2/3] 各ノードにkubeconfigを配布..."
    
    for node in "${NODES[@]}"; do
        echo "  配布中: ${node}"
        
        # リモートノードで .kube ディレクトリ作成
        ssh jaist-lab@${node} "mkdir -p ~/.kube" 2>/dev/null || true
        
        # kubeconfigをコピー
	scp /tmp/kubeconfig-${ENV_NAME}.tmp jaist-lab@${node}:~/.kube/config-${ENV_NAME}
        
        # 権限設定
        ssh jaist-lab@${node} "chmod 600 ~/.kube/config-${ENV_NAME}"
        
        # 確認
        if ssh jaist-lab@${node} "test -f ~/.kube/config-${ENV_NAME} && kubectl get nodes &>/dev/null"; then
            echo "    ✓ ${node} - 配布成功・接続確認OK"
        elif ssh jaist-lab@${node} "test -f ~/.kube/config-${ENV_NAME}"; then
            echo "    ✓ ${node} - 配布成功（接続未確認）"
        else
            echo "    ✗ ${node} - 配布失敗"
        fi
    done
    
    # ローカルの一時ファイル削除
    rm -f /tmp/kubeconfig-${ENV_NAME}.tmp /tmp/kubeconfig-${ENV_NAME}.tmp.bak
    
    echo ""
    echo "[3/3] 配布完了"
    echo "✓ ${ENV_NAME}環境の全ノードに kubeconfig を配布しました"
}

case $ENV_CHOICE in
    1)
        # Production環境
        PROD_NODES=(
            "172.16.100.101"  # master01
            "172.16.100.102"  # master02
            "172.16.100.103"  # master03
            "172.16.100.111"  # node01
            "172.16.100.112"  # node02
            "172.16.100.113"  # node03
        )
        distribute_kubeconfig "production" "172.16.100.101" "${PROD_NODES[@]}"
        ;;
    2)
        # Development環境
        DEV_NODES=(
            "172.16.100.121"  # dev-master01
            "172.16.100.122"  # dev-master02
            "172.16.100.123"  # dev-master03
            "172.16.100.131"  # dev-node01
            "172.16.100.132"  # dev-node02
            "172.16.100.133"  # dev-node03
        )
        distribute_kubeconfig "development" "172.16.100.121" "${DEV_NODES[@]}"
        ;;
    3)
        # 両方
        PROD_NODES=(
            "172.16.100.101" "172.16.100.102" "172.16.100.103"
            "172.16.100.111" "172.16.100.112" "172.16.100.113"
        )
        distribute_kubeconfig "production" "172.16.100.101" "${PROD_NODES[@]}"
        
        DEV_NODES=(
            "172.16.100.121" "172.16.100.122" "172.16.100.123"
            "172.16.100.131" "172.16.100.132" "172.16.100.133"
        )
        distribute_kubeconfig "development" "172.16.100.121" "${DEV_NODES[@]}"
        ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "配布完了サマリー"
echo "=========================================="
echo ""
echo "各ノードでの確認方法:"
echo "  ssh jaist-lab@172.16.100.101"
echo "  export KUBECONFIG=~/.kube/config-production"
echo "  export KUBECONFIG=~/.kube/config-development"
echo "  kubectl get nodes"
echo ""
echo "全ノードでの一括確認:"
echo "  ./verify-kubeconfig-all.sh"
echo "=========================================="
