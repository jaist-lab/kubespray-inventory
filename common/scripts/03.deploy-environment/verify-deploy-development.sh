#!/bin/bash
# デプロイ後検証スクリプト

export KUBECONFIG=~/.kube/config-development

echo "=========================================="
echo "Production環境デプロイ後検証"
echo "=========================================="
echo ""

echo "[1] ノード状態"
kubectl get nodes
echo ""

echo "[2] システムコンポーネント"
kubectl get pods -n kube-system -l tier=control-plane
echo ""

echo "[3] CNI（Calico）"
kubectl get pods -n kube-system -l k8s-app=calico-node
echo ""

echo "[4] CoreDNS"
kubectl get pods -n kube-system -l k8s-app=kube-dns
echo ""

echo "[5] API Server健全性"
for master in master01 master02 master03; do
    echo "  $master:"
    kubectl get pods -n kube-system -l component=kube-apiserver --field-selector spec.nodeName=$master
done
echo ""

echo "[6] クラスタ情報"
kubectl cluster-info
echo ""

echo "=========================================="
echo "✓ 検証完了"
echo "=========================================="
