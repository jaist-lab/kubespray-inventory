#!/bin/bash

# Pod が全ノードで起動しているか確認
kubectl get pods -n kepler -o wide

# DaemonSet の状態確認
kubectl get daemonset -n kepler

# Kepler のログを確認
kubectl logs -n kepler -l app.kubernetes.io/name=kepler --tail=50

# Service の確認
kubectl get svc -n kepler

# ポートフォワードでメトリクスにアクセス
kubectl port-forward -n kepler svc/kepler 9102:9102

# 別のターミナルでメトリクスを取得
curl http://localhost:9102/metrics
