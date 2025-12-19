#!/bin/bash

# cAdvisorのメトリクス確認
kubectl exec -n kube-system -l name=cadvisor -- curl -s localhost:8080/metrics | head -20

# ログ確認
kubectl logs -n kube-system -l name=cadvisor --tail=50

# ServiceMonitorの確認
kubectl get servicemonitor cadvisor -n kube-system

# Prometheus にポートフォワード
echo "kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo " ブラウザで http://localhost:9090 にアクセス"
echo " クエリ: kepler_node_package_joules_total"
