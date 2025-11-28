#!/bin/bash
# DCGM ExporterのServiceMonitorとPrometheusの設定を確認するスクリプト

echo "=== ServiceMonitor設定確認 ==="
# ServiceMonitorのラベル設定とセレクタを確認
# kubectl getが失敗した場合、CRDが存在しない可能性を報告
kubectl get servicemonitor -n monitoring nvidia-dcgm-exporter -o yaml | grep -A 5 -B 5 "labels:" 2>/dev/null || echo "❌ ServiceMonitorリソースが見つからないか、Prometheus Operatorが未導入です。"

echo ""
echo "=== Prometheus設定確認 ==="
# Prometheus Operatorのリソース設定を確認
# kubectl getが失敗した場合、CRDが存在しない可能性を報告
kubectl get prometheus -n monitoring prometheus-cluster-kube-prometheus-prometheus -o jsonpath='{.spec.serviceMonitorNamespaceSelector}' 2>/dev/null | jq . || echo "❌ Prometheusリソースが見つからないか、Prometheus Operatorが未導入です。"

echo ""
echo "=== DCGM Service確認 ==="
# DCGM Exporterが公開しているServiceを確認
kubectl get svc -n gpu-operator -l app=nvidia-dcgm-exporter

echo ""
echo "=== 解決策 ==="
echo "🔥 最優先アクション：ServiceMonitor および Prometheus リソースが存在しないため、Prometheus Operator/Kube-Prometheusが正しくデプロイされているか確認してください。"
echo "1. Prometheus Operatorのデプロイ: 必要に応じて、Kube-Prometheus Stackなどの監視スタックをデプロイしてください。"
echo "2. ServiceMonitor再作成 (デプロイ後): kubectl delete servicemonitor -n monitoring nvidia-dcgm-exporter; kubectl apply -f dcgm-servicemonitor.yaml"
echo "3. Prometheus設定更新 (デプロイ後): kubectl patch prometheus -n monitoring prometheus-cluster-kube-prometheus-prometheus --type='merge' -p='{\"spec\":{\"serviceMonitorNamespaceSelector\":{\"matchNames\":[\"monitoring\",\"gpu-operator\"]}}}'"
