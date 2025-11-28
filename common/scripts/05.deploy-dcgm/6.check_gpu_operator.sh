#!/bin/bash
# DCGM Exporter確認スクリプト（環境別対応版）

echo "📊 DCGM Exporter状況確認"
echo "========================"

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 環境選択
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
        ENV_NAME="Production"
        ;;
    2)
        echo -e "${GREEN}Development環境を選択${NC}"
        export KUBECONFIG=~/.kube/config-development
        GPU_NODES=("rtxsv1")
        ENV_NAME="Development"
        ;;
    *)
        echo -e "${RED}無効な選択肢です。1または2を選択してください。${NC}"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "${ENV_NAME}環境 DCGM Exporter確認"
echo "対象GPUノード: ${GPU_NODES[@]}"
echo "=========================================="
echo ""

# DCGM Exporter状況確認
echo -e "${BLUE}=== DCGM Exporter Pod状況 ===${NC}"
DCGM_PODS=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter -o wide 2>/dev/null)
if [ -z "$DCGM_PODS" ]; then
    echo -e "${RED}❌ DCGM Exporter Podが見つかりませんでした${NC}"
    echo "GPU Operatorが正しくデプロイされているか確認してください"
    exit 1
fi

echo "$DCGM_PODS"
echo ""

# 各GPUノードのDCGM Exporter確認
for node in "${GPU_NODES[@]}"; do
    echo -e "${YELLOW}--- $node 上のDCGM Exporter ---${NC}"
    kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter \
        --field-selector spec.nodeName=$node -o wide 2>/dev/null || \
        echo -e "${YELLOW}  $node にDCGM Exporterなし${NC}"
    echo ""
done

# DCGMメトリクス確認
echo "=========================================="
echo -e "${BLUE}=== DCGMメトリクス確認 ===${NC}"
echo "=========================================="

# 最初のDCGM Exporter Pod名を取得
POD_NAME=$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter -o name 2>/dev/null | head -1 | cut -d/ -f2)

if [ -z "$POD_NAME" ]; then
    echo -e "${RED}❌ DCGM Exporter Podが見つかりませんでした${NC}"
    exit 1
fi

echo -e "${GREEN}対象Pod: ${POD_NAME}${NC}"
echo ""

# ポートフォワーディングをバックグラウンドで開始
echo "Port-forwarding ${POD_NAME}:9400 -> localhost:9400 を開始中..."
kubectl port-forward -n gpu-operator "${POD_NAME}" 9400:9400 > /dev/null 2>&1 &

# バックグラウンドプロセスのPIDを記録
PF_PID=$!

# ポートフォワーディングが開始されるまで待機
echo "待機中（3秒）..."
sleep 3

# curlでメトリクスを取得
echo ""
echo -e "${BLUE}主要GPUメトリクス:${NC}"
echo "----------------------------------------"

if curl -s --max-time 5 http://localhost:9400/metrics >/dev/null 2>&1; then
    # GPU使用率
    echo ""
    echo -e "${YELLOW}📊 GPU使用率 (DCGM_FI_DEV_GPU_UTIL):${NC}"
    curl -s http://localhost:9400/metrics | grep "^DCGM_FI_DEV_GPU_UTIL{" | head -5
    
    # GPU温度
    echo ""
    echo -e "${YELLOW}🌡️  GPU温度 (DCGM_FI_DEV_GPU_TEMP):${NC}"
    curl -s http://localhost:9400/metrics | grep "^DCGM_FI_DEV_GPU_TEMP{" | head -5
    
    # GPUメモリ使用量
    echo ""
    echo -e "${YELLOW}💾 GPUメモリ使用量 (DCGM_FI_DEV_FB_USED):${NC}"
    curl -s http://localhost:9400/metrics | grep "^DCGM_FI_DEV_FB_USED{" | head -5
    
    # 電力使用量
    echo ""
    echo -e "${YELLOW}⚡ 電力使用量 (DCGM_FI_DEV_POWER_USAGE):${NC}"
    curl -s http://localhost:9400/metrics | grep "^DCGM_FI_DEV_POWER_USAGE{" | head -5
    
    echo ""
    echo -e "${GREEN}✅ メトリクス取得成功${NC}"
else
    echo -e "${RED}❌ メトリクス取得失敗${NC}"
    echo "ポートフォワーディングに問題がある可能性があります"
fi

# ポートフォワーディングを停止
kill $PF_PID 2>/dev/null
echo ""
echo "Port-forwardingを停止しました。"

# Service確認
echo ""
echo "=========================================="
echo -e "${BLUE}=== DCGM Exporter Service確認 ===${NC}"
echo "=========================================="
kubectl get svc -n gpu-operator -l app=nvidia-dcgm-exporter 2>/dev/null || \
    echo -e "${YELLOW}⚠️  DCGM Exporter Serviceが見つかりません${NC}"

# GPU監視用コマンド案内
echo ""
echo "=========================================="
echo -e "${BLUE}=== GPU監視用コマンド ===${NC}"
echo "=========================================="
echo ""
echo -e "${YELLOW}1. リアルタイムGPU使用率監視 (nvidia-smi):${NC}"
echo "----------------------------------------"
cat << 'EOF'
watch -n 2 'kubectl exec -n gpu-operator \
  $(kubectl get pods -n gpu-operator -l app=nvidia-device-plugin-daemonset -o name | head -1 | cut -d/ -f2) \
  -- nvidia-smi'
EOF

echo ""
echo -e "${YELLOW}2. GPUメトリクス確認 (DCGM Exporter):${NC}"
echo "----------------------------------------"
echo "# ポートフォワーディング開始"
cat << 'EOF'
kubectl port-forward -n gpu-operator \
  $(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter -o name | head -1 | cut -d/ -f2) \
  9400:9400 &
EOF

echo ""
echo "# メトリクス取得"
echo "curl -s http://localhost:9400/metrics | grep GPU"
echo ""
echo "# ポートフォワーディング停止"
echo "kill %1"

echo ""
echo -e "${YELLOW}3. 特定のGPUノードのメトリクス:${NC}"
echo "----------------------------------------"
for node in "${GPU_NODES[@]}"; do
    echo "# $node のDCGM Exporter"
    cat << EOF
POD=\$(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter \\
  --field-selector spec.nodeName=$node -o name | cut -d/ -f2)
kubectl port-forward -n gpu-operator \$POD 9400:9400 &
curl -s http://localhost:9400/metrics | grep DCGM_FI_DEV
kill %1
EOF
    echo ""
done

echo "=========================================="
echo -e "${GREEN}✅ ${ENV_NAME}環境のDCGM Exporter確認完了${NC}"
echo "=========================================="