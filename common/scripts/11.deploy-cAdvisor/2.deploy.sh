#!/bin/bash

# ServiceAccountを作成
kubectl create serviceaccount cadvisor -n kube-system

# 修正済みYAMLを適用
kubectl apply -f cadvisor-daemonset.yaml

# デプロイ状況を確認
kubectl get daemonset cadvisor -n kube-system
kubectl get pods -n kube-system -l name=cadvisor -o wide

# ServiceMonitorの確認
kubectl get servicemonitor -n monitoring cadvisor
