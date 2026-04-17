#!/bin/bash

# Step 2: argo-server設定（認証無効化・HTTP化）
# 認証を無効にしてHTTPアクセスを可能にする
kubectl patch configmap workflow-controller-configmap -n argo --type merge -p '{"data":{"config":""}}'

# argo-serverのデプロイメント設定変更
kubectl patch deployment argo-server -n argo --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["server", "--auth-mode=server", "--secure=false"]},
  {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/scheme", "value": "HTTP"}
]'

# argo-serverの再起動
kubectl rollout restart deployment argo-server -n argo

# Podが Running になるまで待機
kubectl get pods -n argo -l app=argo-server -w

