#!/bin/bash
#
# argocd専用ネームスペースの作成
kubectl create namespace argocd

# ネームスペース確認
kubectl get namespaces | grep argocd
