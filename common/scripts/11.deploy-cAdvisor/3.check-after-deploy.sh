#!/bin/bash

# cAdvisorのメトリクス確認
kubectl exec -n kube-system -l name=cadvisor -- curl -s localhost:8080/metrics | head -20

# ログ確認
kubectl logs -n kube-system -l name=cadvisor --tail=50

# ServiceMonitorの確認
kubectl get servicemonitor cadvisor -n kube-system
