#!/bin/bash

echo "=== DCGM Exporter状況確認 ==="
kubectl get pods -n gpu-operator | grep dcgm

# DCGM Exporterのメトリクス確認
echo "=== DCGMメトリクス確認 ==="
# DCGM Exporter Pod名を取得
POD_NAME=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter -o name | head -1 | cut -d/ -f2)

if [ -z "$POD_NAME" ]; then
    echo "Error: DCGM Exporter Podが見つかりませんでした。"
else
    # ポートフォワーディングをバックグラウンドで開始
    echo "Port-forwarding ${POD_NAME}:9400 -> localhost:9400 を開始中..."
    kubectl port-forward -n gpu-operator "${POD_NAME}" 9400:9400 > /dev/null 2>&1 &
    
    # バックグラウンドプロセスのPIDを記録
    PF_PID=$!
    
    # ポートフォワーディングが開始されるまで待機
    sleep 3
    
    # ホストのcurlを使用してメトリクスを取得
    echo "ローカルの curl でメトリクスを取得..."
    curl -s http://localhost:9400/metrics | grep -E "(DCGM_FI_DEV_GPU_UTIL|DCGM_FI_DEV_GPU_TEMP|DCGM_FI_DEV_FB_USED)"
    
    # ポートフォワーディングを停止
    kill $PF_PID
    echo "Port-forwardingを停止しました。"
fi

---

# GPU使用状況リアルタイム監視コマンド
echo ""
echo "=== GPU監視用コマンド ==="
echo "# リアルタイムGPU使用率監視 (Pod内でnvidia-smiを実行):"
echo "watch -n 2 'kubectl exec -n gpu-operator \$(kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset -o name | head -1 | cut -d/ -f2) -- nvidia-smi'"

echo ""
echo "# GPUメトリクス確認 (Port-forwardingを使用し、ホスト側からアクセス):"
# 修正箇所: 手動実行用コマンド例を port-forward を使う形に修正
echo "kubectl port-forward -n gpu-operator \$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter -o name | head -1 | cut -d/ -f2) 9400:9400 &"
echo "curl -s http://localhost:9400/metrics | grep GPU"
echo "kill %1 # (ポートフォワーディングを停止する場合)"
