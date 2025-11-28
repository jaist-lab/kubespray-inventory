#!/bin/bash
# GPU Operator + 監視統合 一括動作確認スクリプト（最終修正版）

# =======================================================
# 📌 クリーンアップ関数とトラップ設定 (追加)
# =======================================================
# スクリプト終了時にポートフォワーディングプロセスを確実に停止するための関数
cleanup() {
    if [ -n "$PF_PID" ] && ps -p $PF_PID > /dev/null; then
        kill $PF_PID 2>/dev/null
        echo "Port-forwarding PID $PF_PID を停止しました。"
    fi
    # テストPodが残っていたら削除
    kubectl delete pod gpu-quick-test --ignore-not-found=true >/dev/null 2>&1
}

# スクリプトが終了 (0, 1, 2, 3, EXIT) する際に cleanup 関数を実行
trap cleanup EXIT

echo "🔍 GPU Operator + 監視統合 一括動作確認"
echo "======================================"

# 基本情報収集
NODE_IP=$(kubectl get nodes node101 -o jsonpath='{.status.addresses[0].address}' 2>/dev/null)
PROMETHEUS_EXISTS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)

echo "=== 📊 基本状況確認 ==="
echo "クラスターアクセス: $(kubectl cluster-info --request-timeout=5s >/dev/null 2>&1 && echo '✅ 成功' || echo '❌ 失敗')"
echo "監視システム: $([ $PROMETHEUS_EXISTS -gt 0 ] && echo '✅ 検出済み' || echo 'ℹ️ 未検出')"

# GPU自動検出確認
echo ""
echo "=== 🎯 GPU自動検出確認 ==="
GPU_NODES=$(kubectl get nodes -l feature.node.kubernetes.io/pci-10de.present=true --no-headers | wc -l)
# GPUリソース計算の安全化
GPU_RESOURCES_RAW=$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}' 2>/dev/null | tr ' ' '\n' | grep -v '^$' | paste -sd+ | bc 2>/dev/null || echo "0")
GPU_RESOURCES=${GPU_RESOURCES_RAW:-0}
echo "GPU検出ノード数: $GPU_NODES/2"
echo "GPU総リソース数: $GPU_RESOURCES/8"

# DaemonSet配置確認
echo ""
echo "=== 🚀 DaemonSet配置確認 ==="
kubectl get daemonsets -n gpu-operator -o custom-columns="NAME:.metadata.name,READY:.status.numberReady,DESIRED:.status.desiredNumberScheduled" --no-headers | while read name ready desired; do
    if [[ "$ready" == "$desired" ]] && [[ "$ready" =~ ^[0-9]+$ ]] && [[ "$ready" -gt 0 ]]; then
        echo "✅ $name: $ready/$desired"
    elif [[ "$ready" == "0" ]] && [[ "$desired" == "0" ]]; then
        echo "ℹ️ $name: $ready/$desired (未使用)"
    else
        echo "⚠️ $name: $ready/$desired"
    fi
done

# =======================================================
# 📈 DCGM Exporter動作確認 (修正セクション)
# =======================================================
echo ""
echo "=== 📈 DCGM Exporter動作確認 ==="
DCGM_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter --no-headers | head -1 | awk '{print $1}')
METRIC_COUNT=0
PF_PID="" # port-forwardingのPIDを初期化

if [ -n "$DCGM_POD" ] && [ "$DCGM_POD" != "" ]; then
    echo "DCGM Pod: ✅ $DCGM_POD"
    
    # 🔧 修正: port-forwarding を使ってホスト側から curl でメトリクスを取得
    # バックグラウンドでポートフォワーディングを開始
    kubectl port-forward -n gpu-operator "${DCGM_POD}" 9400:9400 > /dev/null 2>&1 &
    PF_PID=$!
    
    sleep 3 # ポートフォワーディング開始を待つ
    
    # ホスト側の curl でメトリクスを取得し、数をカウント
    METRIC_COUNT=$(curl -s http://localhost:9400/metrics 2>/dev/null | grep -c "DCGM_FI_DEV_GPU_UTIL" || echo "0")
    
    if [ "$METRIC_COUNT" -gt 0 ]; then
        echo "GPU メトリクス数: ✅ $METRIC_COUNT"
    else
        echo "GPU メトリクス数: ❌ 0"
        echo "  📝 ヒント: port-forwarding 経由でメトリクス取得に失敗しました。"
    fi
    
    # PF_PIDはtrapでクリーンアップされるため、ここではkillしない
else
    echo "DCGM Pod: ❌ 未発見"
    METRIC_COUNT=0
fi

# 監視統合確認（Prometheusが存在する場合のみ）
SERVICEMONITOR_EXISTS=0
DCGM_TARGET_COUNT=0
GPU_METRICS_PROM_COUNT=0

if [ $PROMETHEUS_EXISTS -gt 0 ]; then
    echo ""
    echo "=== 🔗 監視統合確認 ==="
    
    # ServiceMonitor確認
    SERVICEMONITOR_EXISTS=$(kubectl get servicemonitor -n monitoring nvidia-dcgm-exporter --no-headers 2>/dev/null | wc -l)
    echo "ServiceMonitor: $([ $SERVICEMONITOR_EXISTS -gt 0 ] && echo '✅ 作成済み' || echo '❌ 未作成')"
    
    if [ $SERVICEMONITOR_EXISTS -gt 0 ]; then
        # Prometheus Target確認
        echo "Target確認中（30秒待機）..."
        sleep 30
        PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers | head -1 | awk '{print $1}')
        if [ -n "$PROMETHEUS_POD" ] && [ "$PROMETHEUS_POD" != "" ]; then
            
            # 🔧 修正: Target確認時に Pod 内の wget が失敗した場合に備えて、Prometheus Pod の内部 IP を使用し、Pod内で curl (または wget) が存在しない場合を考慮する。
            # ただし、Prometheus Podには通常 wget/curl がある前提で、元のロジックを維持し、wget -qO-で成功することを期待する。
            # ここでは Pod 内コマンドの安全性を高めるため、エラー出力をさらに抑制し、数値比較を安全化する。
            DCGM_TARGET_COUNT=$(kubectl exec -n monitoring $PROMETHEUS_POD -c prometheus -- wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | grep -c "dcgm-exporter" 2>/dev/null || echo "0")
            echo "Prometheus Target: $([ $DCGM_TARGET_COUNT -gt 0 ] && echo "✅ ${DCGM_TARGET_COUNT}個検出" || echo "⚠️ 未検出")"
            
            # GPU メトリクス取得確認
            if [ $DCGM_TARGET_COUNT -gt 0 ]; then
                echo "メトリクス取得確認中（20秒待機）..."
                sleep 20
                GPU_METRICS_PROM_COUNT=$(kubectl exec -n monitoring $PROMETHEUS_POD -c prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' 2>/dev/null | grep -c "DCGM_FI_DEV_GPU_UTIL" 2>/dev/null || echo "0")
                echo "GPU メトリクス取得: $([ $GPU_METRICS_PROM_COUNT -gt 0 ] && echo "✅ ${GPU_METRICS_PROM_COUNT}個" || echo "⚠️ 未取得")"
            fi
        else
            echo "Prometheus Pod: ❌ 未発見"
        fi
    fi
fi

# =======================================================
# 🧪 GPU動作テスト (Podのクリーンアップは trap に任せる)
# =======================================================
echo ""
echo "=== 🧪 GPU動作テスト ==="
# 簡易GPUテスト
cat << 'EOF' | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: gpu-quick-test
  namespace: default
spec:
  restartPolicy: Never
  containers:
  - name: gpu-test
    image: nvidia/cuda:12.8-runtime-ubuntu20.04
    command: ["sh", "-c"]
    args:
    - |
      echo "GPU Test Start"
      if command -v nvidia-smi >/dev/null 2>&1; then
        GPU_COUNT=$(nvidia-smi -L | wc -l)
        echo "GPU Test: $GPU_COUNT GPU detected"
      else
        echo "GPU Test: nvidia-smi not available"
      fi
      echo "GPU Test Complete"
      sleep 5
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

# テスト結果確認
echo "GPUテスト実行中（45秒待機）..."
# wait timeoutを長くする
kubectl wait --for=condition=ready pod/gpu-quick-test --timeout=45s >/dev/null 2>&1
sleep 15

TEST_NODE=$(kubectl get pod gpu-quick-test -o jsonpath='{.spec.nodeName}' 2>/dev/null)
TEST_LOG=$(kubectl logs gpu-quick-test 2>/dev/null | grep "GPU Test:" | head -1 || echo "GPU Test: ログ取得失敗")

# Podの削除は trap に移行
# kubectl delete pod gpu-quick-test --ignore-not-found=true >/dev/null 2>&1

echo "テストPod配置先: $([ -n "$TEST_NODE" ] && echo "✅ $TEST_NODE" || echo "❌ 配置失敗")"
echo "GPU認識結果: $TEST_LOG"

echo ""
echo "=== 📊 総合評価 ==="
SUCCESS_SCORE=0

# 数値比較の安全化
echo "GPU検出ノード評価: GPU_NODES=$GPU_NODES"
if [ "$GPU_NODES" -eq 2 ] 2>/dev/null; then
    SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
    echo "✅ GPU自動検出: 成功"
else
    echo "❌ GPU自動検出: 要確認 (検出数: $GPU_NODES/2)"
fi

echo "GPUリソース評価: GPU_RESOURCES=$GPU_RESOURCES"
if [ "$GPU_RESOURCES" -eq 8 ] 2>/dev/null; then
    SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
    echo "✅ GPUリソース認識: 成功"
else
    echo "❌ GPUリソース認識: 要確認 (認識数: $GPU_RESOURCES/8)"
fi

echo "DCGM評価: DCGM_POD=$DCGM_POD, METRIC_COUNT=$METRIC_COUNT"
if [ -n "$DCGM_POD" ] && [ "$METRIC_COUNT" -gt 0 ] 2>/dev/null; then
    SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
    echo "✅ DCGM Exporter: 成功"
else
    echo "❌ DCGM Exporter: 要確認"
fi

echo "テスト評価: TEST_NODE=$TEST_NODE"
if [ -n "$TEST_NODE" ]; then
    SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
    echo "✅ GPU動作テスト: 成功"
else
    echo "❌ GPU動作テスト: 要確認"
fi

# 監視統合評価（任意）
echo "監視統合評価: PROMETHEUS_EXISTS=$PROMETHEUS_EXISTS, SERVICEMONITOR_EXISTS=$SERVICEMONITOR_EXISTS, DCGM_TARGET_COUNT=$DCGM_TARGET_COUNT"
if [ $PROMETHEUS_EXISTS -gt 0 ]; then
    if [ $SERVICEMONITOR_EXISTS -gt 0 ] && [ $DCGM_TARGET_COUNT -gt 0 ] 2>/dev/null; then
        SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
        echo "✅ 監視統合: 成功"
    else
        echo "⚠️ 監視統合: 要調整"
    fi
else
    SUCCESS_SCORE=$((SUCCESS_SCORE + 20))  # 単体でも成功とみなす
    echo "ℹ️ 監視統合: 対象外（GPU Operator単体）"
fi

echo ""
echo "🎯 総合成功度: ${SUCCESS_SCORE}%"

if [ $SUCCESS_SCORE -eq 100 ]; then
    echo "🎉 GPU環境構築完全成功！"
elif [ $SUCCESS_SCORE -ge 80 ]; then
    echo "✅ GPU環境構築成功（一部調整推奨）"
else
    echo "⚠️ GPU環境構築要確認（詳細診断推奨）"
fi

echo ""
echo "=== 📋 アクセス情報 ==="
echo "GPU確認: kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'"
if [ $PROMETHEUS_EXISTS -gt 0 ]; then
    echo "Prometheus: http://$NODE_IP:32090/targets"
    echo "Grafana: http://$NODE_IP:32000 (admin/gpu-monitoring-2024)"
fi

echo ""
echo "=== 🔧 次のアクション ==="
if [ $SUCCESS_SCORE -lt 80 ]; then
    echo "詳細診断推奨: ./detailed-diagnosis.sh"
    echo "簡易修復: ./simple-troubleshoot.sh"
fi

echo ""
echo "✅ 一括動作確認完了"
