#!/bin/bash
# GPU Operator Helm準備スクリプト（環境別対応版）

echo "🚀 GPU Operator Helm準備"
echo "======================="

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 環境選択
echo "GPU Operatorをデプロイする環境を選択してください:"
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
        echo -e "${YELLOW}Development環境にはGPUノードが存在しません（rtxsv1は除外済み）${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}無効な選択肢です。1または2を選択してください。${NC}"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "${ENV_NAME}環境 GPU Operator準備"
echo "対象ノード: ${GPU_NODES[@]}"
echo "=========================================="
echo ""

# Kubernetes接続確認
echo -e "${BLUE}📊 Kubernetes接続確認${NC}"
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✅ Kubernetesクラスタに接続成功${NC}"
    kubectl get nodes -o wide | grep -E "NAME|$(IFS='|'; echo "${GPU_NODES[*]}")" || kubectl get nodes -o wide
else
    echo -e "${RED}❌ Kubernetesクラスタに接続できません${NC}"
    echo "KUBECONFIG: $KUBECONFIG"
    exit 1
fi

echo ""
echo "=========================================="
echo "### 1. Helmリポジトリの設定"
echo "=========================================="

# NVIDIAのHelmリポジトリを追加
echo -e "${BLUE}📦 NVIDIAリポジトリ追加中...${NC}"
if helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null; then
    echo -e "${GREEN}✅ NVIDIAリポジトリ追加成功${NC}"
else
    echo -e "${YELLOW}ℹ️  NVIDIAリポジトリは既に追加済み（スキップ）${NC}"
fi

# リポジトリの更新
echo ""
echo -e "${BLUE}🔄 リポジトリ更新中...${NC}"
helm repo update
echo -e "${GREEN}✅ リポジトリ更新完了${NC}"

# 利用可能なGPU Operatorバージョンの確認
echo ""
echo -e "${BLUE}📋 利用可能なGPU Operatorバージョン（最新10件）:${NC}"
helm search repo nvidia/gpu-operator --versions | head -10

echo ""
echo "=========================================="
echo "### 2. ネームスペース作成"
echo "=========================================="

# 既存のネームスペース確認
if kubectl get namespace gpu-operator &>/dev/null; then
    echo -e "${YELLOW}ℹ️  gpu-operatorネームスペースは既に存在します${NC}"
    echo ""
    echo -e "${BLUE}既存のネームスペース情報:${NC}"
    kubectl get namespace gpu-operator -o wide
    echo ""
    read -p "既存のネームスペースを削除して再作成しますか? (y/N): " RECREATE
    if [[ "$RECREATE" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}🗑️  既存のネームスペース削除中...${NC}"
        kubectl delete namespace gpu-operator
        echo -e "${GREEN}✅ ネームスペース削除完了${NC}"
        echo ""
        echo -e "${BLUE}📁 gpu-operatorネームスペース作成中...${NC}"
        kubectl create namespace gpu-operator
        echo -e "${GREEN}✅ ネームスペース作成完了${NC}"
    else
        echo -e "${GREEN}✅ 既存のネームスペースを使用します${NC}"
    fi
else
    # gpu-operator専用ネームスペースの作成
    echo -e "${BLUE}📁 gpu-operatorネームスペース作成中...${NC}"
    kubectl create namespace gpu-operator
    echo -e "${GREEN}✅ ネームスペース作成完了${NC}"
fi

# ネームスペース確認
echo ""
echo -e "${BLUE}📊 ネームスペース確認:${NC}"
kubectl get namespaces | grep -E "NAME|gpu-operator"

echo ""
echo "=========================================="
echo "準備完了サマリー"
echo "=========================================="
echo "環境: ${ENV_NAME}"
echo "KUBECONFIG: $KUBECONFIG"
echo "対象GPUノード: ${GPU_NODES[@]}"
echo "ネームスペース: gpu-operator"
echo ""
echo -e "${GREEN}✅ ${ENV_NAME}環境のGPU Operator Helm準備完了${NC}"
echo ""
echo "次のステップ:"
echo "  - GPU Operatorのvalues.yamlを確認"
echo "  - helm install コマンドでデプロイ実行"
echo "=========================================="