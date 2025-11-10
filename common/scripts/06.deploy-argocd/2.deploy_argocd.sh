#!/bin/bash

# ArgoCD インストールスクリプト（修正版）

echo "🚀 ArgoCD インストール開始"
echo "================================="

# argocd専用ネームスペースの作成
echo "=== ネームスペース作成 ==="
kubectl create namespace argocd

# ネームスペース確認
kubectl get namespaces | grep argocd

echo ""
echo "=== ArgoCD マニフェスト適用 ==="
# 最新の安定版ArgoCD インストール
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo ""
echo "=== Pod起動待ち ==="
echo "（この処理には3-5分程度かかります）"

# Pod起動待ち（より確実な方法）
echo "ArgoCD Server起動待ち..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo "ArgoCD Dex Server起動待ち..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-dex-server -n argocd

echo "ArgoCD Repo Server起動待ち..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd

echo "ArgoCD Application Controller起動待ち..."
kubectl wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/name=argocd-application-controller -n argocd

echo ""
echo "=== ArgoCD Pod状態確認 ==="
kubectl get pods -n argocd

echo ""
echo "✅ ArgoCD インストール完了"
