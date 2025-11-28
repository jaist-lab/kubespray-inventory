#!/bin/bash
# 手動設定削除スクリプト

echo "🧹 手動設定削除（完全自動検出準備）"
echo "================================="

echo "=== 手動Taint削除 ==="
# 既存の手動Taintを削除
kubectl taint node dlcsv1 dedicated=gpu-compute:NoSchedule- 2>/dev/null && echo "dlcsv1のTaint削除完了" || echo "dlcsv1にTaintなし"
kubectl taint node dlcsv2 dedicated=gpu-compute:NoSchedule- 2>/dev/null && echo "dlcsv2のTaint削除完了" || echo "dlcsv2にTaintなし"

echo ""
echo "=== 手動ラベル削除 ==="
# 既存の手動ラベルを削除
kubectl label node dlcsv1 workload-type- 2>/dev/null && echo "dlcsv1のラベル削除完了" || echo "dlcsv1にラベルなし"
kubectl label node dlcsv2 workload-type- 2>/dev/null && echo "dlcsv2のラベル削除完了" || echo "dlcsv2にラベルなし"

echo ""
echo "=== 削除後確認 ==="
echo "Taint状況:"
kubectl get nodes dlcsv1 dlcsv2 -o custom-columns="NAME:.metadata.name,TAINTS:.spec.taints[*].key"

echo ""
echo "✅ 手動設定削除完了 - 完全自動検出の準備完了"
