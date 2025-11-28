#!/bin/bash
# GPU Operatorインストールスクリプト（監視統合対応修正版）

echo "🚀 NVIDIA GPU Operator インストール開始（監視統合対応版）"
echo "========================================================"

# 前提条件確認
echo "📋 前提条件確認..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Kubernetesクラスターに接続できません"
    exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
    echo "❌ Helmがインストールされていません"
    exit 1
fi

# 🔧 追加: 監視システム確認
echo ""
echo "🔍 監視システム確認..."
PROMETHEUS_EXISTS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)
if [ $PROMETHEUS_EXISTS -gt 0 ]; then
    echo "✅ Prometheusが稼働中です（監視統合を有効化）"
    MONITORING_INTEGRATION=true
else
    echo "⚠️ Prometheusが見つかりません（監視統合を無効化）"
    MONITORING_INTEGRATION=false
fi

# GPU検出確認（ハードウェアレベル）
echo ""
echo "🔍 GPU自動検出確認..."
GPU_DETECTION=false
for node_ip in 172.16.100.31 172.16.100.32; do
    gpu_count=$(ssh jaist-lab@$node_ip "lspci | grep -i nvidia | wc -l" 2>/dev/null)
    if [ "$gpu_count" -gt 0 ]; then
        echo "✅ $(ssh jaist-lab@$node_ip "hostname" 2>/dev/null): NVIDIA GPU ${gpu_count}個検出"
        GPU_DETECTION=true
    fi
done

if [ "$GPU_DETECTION" = false ]; then
    echo "❌ GPUハードウェアが検出されません"
    exit 1
fi

# 🔧 修正: 既存GPU Operator削除（完全削除）
echo ""
echo "🧹 既存GPU Operator削除..."
helm uninstall gpu-operator -n gpu-operator 2>/dev/null || echo "既存リリースなし"



# GPU Operatorインストール
echo ""
echo "🚀 GPU Operatorインストール開始（監視統合対応モード）..."
echo "（この処理には10-15分程度かかります）"

helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --values gpu-operator-values.yaml \
  --wait \
  --timeout 20m

INSTALL_RESULT=$?

if [ $INSTALL_RESULT -eq 0 ]; then
    echo ""
    echo "✅ GPU Operatorインストール完了!"
    
    # 🔧 追加: 監視統合設定（Prometheusが存在する場合）
    if [ "$MONITORING_INTEGRATION" = true ]; then
        echo ""
        echo "🔗 監視システム統合設定開始..."
        
        # Pod起動待ち
        echo "DCGM Exporter起動待ち（60秒）..."
        sleep 60
        
        # DCGM Exporter Service確認
        echo "DCGM Exporter Service確認:"
        kubectl get svc -n gpu-operator -l app=nvidia-dcgm-exporter
        
        # ServiceMonitor作成
        echo ""
        echo "ServiceMonitor作成中..."
        kubectl apply -f dcgm-servicemonitor.yaml

        # 🔧 重要: Prometheus設定更新
        echo ""
        echo "Prometheus設定更新中..."
        kubectl patch prometheus -n monitoring prometheus-cluster-kube-prometheus-prometheus --type='merge' -p='{
            "spec": {
                "serviceMonitorNamespaceSelector": {
                    "matchNames": ["monitoring", "gpu-operator", "kube-system"]
                }
            }
        }' 2>/dev/null || echo "Prometheus設定更新スキップ"
        
        echo "✅ 監視システム統合設定完了"
    fi
    
else
    echo ""
    echo "❌ GPU Operatorインストール失敗"
    kubectl get events -n gpu-operator --sort-by='.lastTimestamp' | tail -10
    exit 1
fi

# インストール状況確認
echo ""
echo "📊 インストール状況確認..."
kubectl get pods -n gpu-operator

echo ""
echo "🎉 完全自動検出インストール完了!"

# 🔧 追加: 監視統合確認
if [ "$MONITORING_INTEGRATION" = true ]; then
    echo ""
    echo "📊 監視統合状況確認..."
    echo "ServiceMonitor確認:"
    kubectl get servicemonitor -n monitoring nvidia-dcgm-exporter
    
    echo ""
    echo "5分後にPrometheus Targetsで確認してください:"
    NODE_IP=$(kubectl get nodes node101 -o jsonpath='{.status.addresses[0].address}' 2>/dev/null)
    echo "  Prometheus: http://$NODE_IP:32090/targets"
fi
