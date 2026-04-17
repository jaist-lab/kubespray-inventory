#!/bin/bash
# Argo Workflows用namespace作成
kubectl create namespace argo

# 公式マニフェストで一括インストール
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.7.1/install.yaml

# インストール確認
kubectl get pods -n argo
