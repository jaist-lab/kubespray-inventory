#!/bin/bash

set -e

# 使用方法
function usage() {
    echo "使用方法: $0 <cluster-name>"
    echo ""
    echo "  cluster-name: production または development, sandbox"
    echo ""
    echo "例:"
    echo "  $0 production"
    echo "  $0 development"
    echo "  $0 sandbox"
    exit 1
}

# 引数チェック
if [ $# -ne 1 ]; then
    usage
fi

CLUSTER=$1
SCRIPT_DIR=$(cd $(dirname $0); pwd)

# Kubeconfig の設定
case $CLUSTER in
    production)
        export KUBECONFIG=/home/jaist-lab/.kube/config-production
        ;;
    development)
        export KUBECONFIG=/home/jaist-lab/.kube/config-development
        ;;
    sandbox)
        export KUBECONFIG=/home/jaist-lab/.kube/config-sandbox
        ;;
    *)
        echo "エラー: 不正なクラスター名: $CLUSTER"
        usage
        ;;
esac

echo "=== Fluent Bit デプロイ ==="
echo "対象クラスタ: $CLUSTER"
echo "Kubeconfig: $KUBECONFIG"
echo ""

# Namespace の作成
echo "1. Namespace を作成..."
kubectl apply -f $SCRIPT_DIR/namespace.yaml

# ConfigMap の適用
echo "2. ConfigMap を作成..."
kubectl apply -f $SCRIPT_DIR/configmap.yaml

# ServiceAccount の作成
echo "3. ServiceAccount を作成..."
kubectl apply -f $SCRIPT_DIR/serviceaccount.yaml

# ClusterRole の作成
echo "4. ClusterRole を作成..."
kubectl apply -f $SCRIPT_DIR/clusterrole.yaml

# ClusterRoleBinding の作成
echo "5. ClusterRoleBinding を作成..."
kubectl apply -f $SCRIPT_DIR/clusterrolebinding.yaml

# Service の作成
echo "6. Service を作成..."
kubectl apply -f $SCRIPT_DIR/service.yaml

# DaemonSet の作成
echo "7. DaemonSet を作成..."
kubectl apply -f $SCRIPT_DIR/daemonset.yaml

echo ""
echo "=== デプロイ完了 ==="
echo ""
echo "確認コマンド:"
echo "  export KUBECONFIG=$KUBECONFIG"
echo "  kubectl get pods -n logging"
echo "  kubectl logs -n logging -l app.kubernetes.io/name=fluent-bit -f"
echo "  kubectl describe configmap -n logging fluent-bit"
