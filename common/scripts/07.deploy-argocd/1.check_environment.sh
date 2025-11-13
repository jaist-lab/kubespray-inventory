#!/bin/bash

# ArgoCD インストール前環境確認

echo "🔍 ArgoCD インストール前環境確認"
echo "=============================="

echo "=== Kubernetesクラスター状態確認 ==="
kubectl cluster-info
kubectl get nodes

echo ""
echo "=== ネームスペース確認 ==="
kubectl get namespaces | grep -E "(argocd|argo-cd)" || echo "ArgoCD関連ネームスペースなし"

echo ""
echo "=== ストレージクラス確認 ==="
kubectl get storageclass

echo ""
echo "=== 既存Ingressリソース確認 ==="
kubectl get ingress --all-namespaces

echo ""
echo "=== ノードポート使用状況確認 ==="
kubectl get svc --all-namespaces | grep NodePort

echo ""
echo "✅ 環境確認完了"
