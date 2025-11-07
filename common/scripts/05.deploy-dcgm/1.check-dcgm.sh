#!/bin/bash
# 環境確認スクリプト（完全自動検出版）

echo "🔍 GPU環境確認（完全自動検出版）"
echo "=============================="

# Kubernetesクラスター状態確認
echo "📊 Kubernetesクラスター状態:"
kubectl get nodes -o wide

# 手動ラベル確認（削除対象）
echo ""
echo "🏷️ 手動ラベル確認（削除予定）:"
kubectl get nodes dlcsv1 dlcsv2 --show-labels | grep -E "(workload-type|dedicated)" || echo "手動ラベルなし"

# 手動Taint確認（削除対象）
echo ""
echo "🔒 手動Taint確認（削除予定）:"
kubectl get nodes dlcsv1 dlcsv2 -o custom-columns="NAME:.metadata.name,TAINTS:.spec.taints[*].key" | grep -E "(dedicated|gpu-compute)" || echo "手動Taintなし"

# Helm確認
echo ""
echo "📦 Helm状態確認:"
helm version --short

# 🔧 NEW: 監視システム確認
echo ""
echo "📊 監視システム確認:"
PROMETHEUS_EXISTS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)
if [ $PROMETHEUS_EXISTS -gt 0 ]; then
    echo "✅ Prometheus監視システム検出 - 監視統合を有効化します"
    kubectl get svc -n monitoring | grep prometheus
else
    echo "ℹ️ Prometheus監視システム未検出 - GPU Operator単体で進行します"
fi

# 自動検出の前提確認
echo ""
echo "🔍 GPU自動検出の前提確認:"
echo "NVIDIA GPUハードウェアの存在確認..."
for node_ip in 172.16.100.31 172.16.100.32; do
    node_name=$(ssh jaist-lab@$node_ip "hostname" 2>/dev/null)
    gpu_check=$(ssh jaist-lab@$node_ip "lspci | grep -i nvidia | wc -l" 2>/dev/null)
    echo "  $node_name: NVIDIA デバイス ${gpu_check}個検出"
done

echo ""
echo "✅ 環境確認完了 - 完全自動検出モードで進行します"

