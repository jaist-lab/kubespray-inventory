#!/bin/bash
# Grafana Ingressのデプロイスクリプト
set -e
# Namespaceの指定
NAMESPACE="monitoring"
cd $(dirname $0)

# 1. Ingressリソースを作成
kubectl apply -f grafana-ingress.yaml

# 2. Ingressの状態確認
kubectl get ingress -n $NAMESPACE

# 3. 詳細情報確認
kubectl describe ingress grafana-ingress -n $NAMESPACE

# 4. Serviceの確認（ポート番号確認）
kubectl get svc prometheus-stack-grafana -n $NAMESPACE
