#!/bin/bash

# マニフェストファイルを適用
kubectl apply -f cadvisor-daemonset.yaml

# デプロイ状況確認
kubectl get daemonset cadvisor -n kube-system

# 全ノードでの稼働確認
kubectl get pods -n kube-system -l name=cadvisor -o wide
