#!/bin/bash
# GPU Operator + 監視統合 一括動作確認スクリプト（環境別対応版）

echo "🔍 GPU Operator + 監視統合 一括動作確認"
echo "========================================"

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =======================================================
# 📌 環境選択
# =======================================================
echo "確認する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo ""
read -p "選択 (1/2): " ENV_CHOICE

# 環境別の設定
case $ENV_CHOICE in
    1)
        echo -e "${GREEN}Production環境を選択${NC}"
        export KUBECONFIG=~/.kube/config-production
        GPU_NODES=("dlcsv1" "dlcsv2")
        EXPECTED_GPU_COUNT=8  # 期待されるGPU総数（要調整）
        EXPECTED_NODE_COUNT=2
        ENV_NAME="Production"
        ;;
    2)
        echo -e "${GREEN}Development環境を選択${NC}"
        export KUBECONFIG=~/.kube/config-development
        GPU_NODES=("rtxsv1")
        EXPECTED_GPU_COUNT=1  # RTX 4090 x 1
        EXPECTED_NODE_COUNT=1
        ENV_NAME="Development"
        ;;
    *)
        echo -e "${RED}無効な選択肢です。1または2を選択してください。${NC}"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "${ENV_NAME}環境 一括動作確認"
echo "対象GPUノード: ${GPU_NODES[@]}"
echo "期待GPU数: ${EXPECTED_GPU_COUNT}"
echo "=========================================="
echo ""

# =======================================================
# 📌 クリーンアップ関数とトラップ設定
# =======================================================
cleanup() {
    if [ -n "$PF_PID" ] && ps -p $PF_PID > /dev/null 2>&1; then
        kill $PF_PID 2>/dev/null
        echo "Port-forwarding PID $PF_PID を停止しました。"
    fi
    # テストPodが残っていたら削除
    kubectl delete pod gpu-quick-test --ignore-not-found=true >/dev/null 2>&1
}

trap cleanup EXIT

# 基本情報収集
FIRST_NODE="${GPU_NODES[0]}"
NODE_IP=$(kubectl get nodes $FIRST_NODE -o jsonpath='{.status.addresses[0].address}' 2>/dev/null)
PROMETHEUS_EXISTS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)

echo -e "${BLUE}=== 📊 基本状況確認 ===${NC}"
CLUSTER_ACCESS=$(kubectl cluster-info --request-timeout=5s >/dev/null 2>&1 && echo "✅ 成功" || echo "❌ 失敗")
echo "クラスターアクセス: $CLUSTER_ACCESS"
echo "監視システム: $([ $PROMETHEUS_EXISTS -gt 0 ] && echo '✅ 検出済み' || echo 'ℹ️  未検出')"
echo "ノードIP: ${NODE_IP:-未取得}"

# GPU自動検出確認
echo ""
echo -e "${BLUE}=== 🎯 GPU自動検出確認 ===${NC}"

# GPUノード数確認（環境に応じた）
DETECTED_GPU_NODES=0
for node in "${GPU_NODES[@]}"; do
    if kubectl get node $node -o json 2>/dev/null | jq -e '.metadata.labels["feature.node.kubernetes.io/pci-10de.present"] == "true"' >/dev/null 2>&1; then
        DETECTED_GPU_NODES=$((DETECTED_GPU_NODES + 1))
    fi
done

# GPUリソース計算の安全化
GPU_RESOURCES=0
for node in "${GPU_NODES[@]}"; do
    NODE_GPU=$(kubectl get node $node -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
    GPU_RESOURCES=$((GPU_RESOURCES + NODE_GPU))
done

echo "GPU検出ノード数: ${DETECTED_GPU_NODES}/${EXPECTED_NODE_COUNT}"
echo "GPU総リソース数: ${GPU_RESOURCES}/${EXPECTED_GPU_COUNT}"

# 各ノードのGPU数表示
for node in "${GPU_NODES[@]}"; do
    NODE_GPU=$(kubectl get node $node -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' 2>/dev/null || echo "0")
    echo "  - ${node}: ${NODE_GPU} GPU"
done

# DaemonSet配置確認
echo ""
echo -e "${BLUE}=== 🚀 DaemonSet配置確認 ===${NC}"
kubectl get daemonsets -n gpu-operator -o custom-columns="NAME:.metadata.name,READY:.status.numberReady,DESIRED:.status.desiredNumberScheduled" --no-headers 2>/dev/null | while read name ready desired; do
    if [[ "$ready" == "$desired" ]] && [[ "$ready" =~ ^[0-9]+$ ]] && [[ "$ready" -gt 0 ]]; then
        echo -e "${GREEN}✅ $name: $ready/$desired${NC}"
    elif [[ "$ready" == "0" ]] && [[ "$desired" == "0" ]]; then
        echo -e "${YELLOW}ℹ️  $name: $ready/$desired (未使用)${NC}"
    else
        echo -e "${YELLOW}⚠️  $name: $ready/$desired${NC}"
    fi
done

# =======================================================
# 📈 DCGM Exporter動作確認
# =======================================================
echo ""
echo -e "${BLUE}=== 📈 DCGM Exporter動作確認 ===${NC}"
DCGM_POD=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter --no-headers 2>/dev/null | head -1 | awk '{print $1}')
METRIC_COUNT=0
PF_PID=""

if [ -n "$DCGM_POD" ] && [ "$DCGM_POD" != "" ]; then
    echo "DCGM Pod: ✅ $DCGM_POD"
    
    # port-forwarding を使ってホスト側から curl でメトリクスを取得
    kubectl port-forward -n gpu-operator "${DCGM_POD}" 9400:9400 > /dev/null 2>&1 &
    PF_PID=$!
    
    echo "ポートフォワーディング開始（3秒待機）..."
    sleep 3
    
    # ホスト側の curl でメトリクスを取得し、数をカウント
    METRIC_COUNT=$(curl -s --max-time 5 http://localhost:9400/metrics 2>/dev/null | grep -c "DCGM_FI_DEV_GPU_UTIL" || echo "0")
    
    if [ "$METRIC_COUNT" -gt 0 ]; then
        echo -e "${GREEN}GPU メトリクス数: ✅ $METRIC_COUNT${NC}"
    else
        echo -e "${RED}GPU メトリクス数: ❌ 0${NC}"
        echo "  📝 ヒント: port-forwarding 経由でメトリクス取得に失敗しました。"
    fi
else
    echo -e "${RED}DCGM Pod: ❌ 未発見${NC}"
    METRIC_COUNT=0
fi

# 監視統合確認（Prometheusが存在する場合のみ）
SERVICEMONITOR_EXISTS=0
DCGM_TARGET_COUNT=0
GPU_METRICS_PROM_COUNT=0

if [ $PROMETHEUS_EXISTS -gt 0 ]; then
    echo ""
    echo -e "${BLUE}=== 🔗 監視統合確認 ===${NC}"
    
    # ServiceMonitor確認
    SERVICEMONITOR_EXISTS=$(kubectl get servicemonitor -n monitoring nvidia-dcgm-exporter --no-headers 2>/dev/null | wc -l)
    echo "ServiceMonitor: $([ $SERVICEMONITOR_EXISTS -gt 0 ] && echo '✅ 作成済み' || echo '❌ 未作成')"
    
    if [ $SERVICEMONITOR_EXISTS -gt 0 ]; then
        # Prometheus Target確認
        echo "Target確認中（30秒待機）..."
        sleep 30
        PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | head -1 | awk '{print $1}')
        if [ -n "$PROMETHEUS_POD" ] && [ "$PROMETHEUS_POD" != "" ]; then
            DCGM_TARGET_COUNT=$(kubectl exec -n monitoring $PROMETHEUS_POD -c prometheus -- wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null | grep -c "dcgm-exporter" 2>/dev/null || echo "0")
            echo "Prometheus Target: $([ $DCGM_TARGET_COUNT -gt 0 ] && echo -e "${GREEN}✅ ${DCGM_TARGET_COUNT}個検出${NC}" || echo -e "${YELLOW}⚠️  未検出${NC}")"
            
            # GPU メトリクス取得確認
            if [ $DCGM_TARGET_COUNT -gt 0 ]; then
                echo "メトリクス取得確認中（20秒待機）..."
                sleep 20
                GPU_METRICS_PROM_COUNT=$(kubectl exec -n monitoring $PROMETHEUS_POD -c prometheus -- wget -qO- 'http://localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' 2>/dev/null | grep -c "DCGM_FI_DEV_GPU_UTIL" 2>/dev/null || echo "0")
                echo "GPU メトリクス取得: $([ $GPU_METRICS_PROM_COUNT -gt 0 ] && echo -e "${GREEN}✅ ${GPU_METRICS_PROM_COUNT}個${NC}" || echo -e "${YELLOW}⚠️  未取得${NC}")"
            fi
        else
            echo -e "${RED}Prometheus Pod: ❌ 未発見${NC}"
        fi
    fi
fi

# =======================================================
# 🧪 GPU動作テスト
# =======================================================
echo ""
echo -e "${BLUE}=== 🧪 GPU動作テスト ===${NC}"

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
    image: nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04
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

echo "GPUテスト実行中（45秒待機）..."
kubectl wait --for=condition=ready pod/gpu-quick-test --timeout=45s >/dev/null 2>&1
sleep 15

TEST_NODE=$(kubectl get pod gpu-quick-test -o jsonpath='{.spec.nodeName}' 2>/dev/null)
TEST_LOG=$(kubectl logs gpu-quick-test 2>/dev/null | grep "GPU Test:" | head -1 || echo "GPU Test: ログ取得失敗")

echo "テストPod配置先: $([ -n "$TEST_NODE" ] && echo -e "${GREEN}✅ $TEST_NODE${NC}" || echo -e "${RED}❌ 配置失敗${NC}")"
echo "GPU認識結果: $TEST_LOG"

# =======================================================
# 📊 総合評価
# =======================================================
echo ""
echo -e "${BLUE}=== 📊 総合評価 ===${NC}"
SUCCESS_SCORE=0

# GPU検出ノード評価
if [ "$DETECTED_GPU_NODES" -eq "$EXPECTED_NODE_COUNT" ] 2>/dev/null; then
    SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
    echo -e "${GREEN}✅ GPU自動検出: 成功 (${DETECTED_GPU_NODES}/${EXPECTED_NODE_COUNT})${NC}"
else
    echo -e "${RED}❌ GPU自動検出: 要確認 (検出数: ${DETECTED_GPU_NODES}/${EXPECTED_NODE_COUNT})${NC}"
fi

# GPUリソース評価
if [ "$GPU_RESOURCES" -eq "$EXPECTED_GPU_COUNT" ] 2>/dev/null; then
    SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
    echo -e "${GREEN}✅ GPUリソース認識: 成功 (${GPU_RESOURCES}/${EXPECTED_GPU_COUNT})${NC}"
else
    echo -e "${RED}❌ GPUリソース認識: 要確認 (認識数: ${GPU_RESOURCES}/${EXPECTED_GPU_COUNT})${NC}"
fi

# DCGM評価
if [ -n "$DCGM_POD" ] && [ "$METRIC_COUNT" -gt 0 ] 2>/dev/null; then
    SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
    echo -e "${GREEN}✅ DCGM Exporter: 成功${NC}"
else
    echo -e "${RED}❌ DCGM Exporter: 要確認${NC}"
fi

# テスト評価
if [ -n "$TEST_NODE" ]; then
    SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
    echo -e "${GREEN}✅ GPU動作テスト: 成功${NC}"
else
    echo -e "${RED}❌ GPU動作テスト: 要確認${NC}"
fi

# 監視統合評価
if [ $PROMETHEUS_EXISTS -gt 0 ]; then
    if [ $SERVICEMONITOR_EXISTS -gt 0 ] && [ $DCGM_TARGET_COUNT -gt 0 ] 2>/dev/null; then
        SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
        echo -e "${GREEN}✅ 監視統合: 成功${NC}"
    else
        echo -e "${YELLOW}⚠️  監視統合: 要調整${NC}"
    fi
else
    SUCCESS_SCORE=$((SUCCESS_SCORE + 20))
    echo -e "${BLUE}ℹ️  監視統合: 対象外（GPU Operator単体）${NC}"
fi

echo ""
echo -e "${BLUE}🎯 総合成功度: ${SUCCESS_SCORE}%${NC}"

if [ $SUCCESS_SCORE -eq 100 ]; then
    echo -e "${GREEN}🎉 ${ENV_NAME}環境 GPU環境構築完全成功！${NC}"
elif [ $SUCCESS_SCORE -ge 80 ]; then
    echo -e "${GREEN}✅ ${ENV_NAME}環境 GPU環境構築成功（一部調整推奨）${NC}"
else
    echo -e "${YELLOW}⚠️  ${ENV_NAME}環境 GPU環境構築要確認（詳細診断推奨）${NC}"
fi

echo ""
echo -e "${BLUE}=== 📋 アクセス情報 ===${NC}"
echo "GPU確認: kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'"
if [ $PROMETHEUS_EXISTS -gt 0 ] && [ -n "$NODE_IP" ]; then
    echo "Prometheus: http://$NODE_IP:32090/targets"
    echo "Grafana: http://$NODE_IP:32000"
fi

echo ""
echo -e "${BLUE}=== 🔧 次のアクション ===${NC}"
if [ $SUCCESS_SCORE -lt 80 ]; then
    echo "詳細診断推奨: kubectl describe nodes ${GPU_NODES[@]}"
    echo "Pod確認: kubectl get pods -n gpu-operator -o wide"
fi

echo ""
echo -e "${GREEN}✅ ${ENV_NAME}環境 一括動作確認完了${NC}"