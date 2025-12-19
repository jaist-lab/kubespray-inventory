#!/bin/bash

# 既存のリソースをクリーンアップ
kubectl delete service cadvisor -n kube-system --ignore-not-found
kubectl delete servicemonitor cadvisor -n monitoring --ignore-not-found
kubectl delete daemonset cadvisor -n kube-system --ignore-not-found

# ServiceAccountを作成
kubectl create serviceaccount cadvisor -n kube-system

# 修正済みYAMLを適用
kubectl apply -f cadvisor-daemonset-fixed.yaml

# デプロイ状況を確認
kubectl get daemonset cadvisor -n kube-system
kubectl get pods -n kube-system -l name=cadvisor -o wide

# ServiceMonitorの確認
kubectl get servicemonitor -n monitoring cadvisor
