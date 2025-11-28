#!/bin/bash
# GPUノード準備スクリプト（環境別対応版・条件付き実行）

echo "🔧 GPUノード準備確認"
echo "=================="

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 環境選択
echo "GPUノード準備を実行する環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo ""
read -p "選択 (1/2): " ENV_CHOICE

# 環境別の設定
case $ENV_CHOICE in
    1)
        echo -e "${GREEN}Production環境を選択${NC}"
        export KUBECONFIG=~/.kube/config-production
        GPU_NODES=("172.16.100.31" "172.16.100.32")
        NODE_NAMES=("dlcsv1" "dlcsv2")
        ENV_NAME="Production"
        ;;
    2)
        echo -e "${GREEN}Development環境を選択${NC}"
        export KUBECONFIG=~/.kube/config-development
        GPU_NODES=("172.16.100.41")
        NODE_NAMES=("rtxsv1")
        ENV_NAME="Development"
        ;;
    *)
        echo -e "${RED}無効な選択肢です。1または2を選択してください。${NC}"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "${ENV_NAME}環境のGPUノード準備"
echo "対象ノード: ${NODE_NAMES[@]}"
echo "=========================================="
echo ""

# 準備が必要かどうかを確認
need_preparation=false

for i in "${!GPU_NODES[@]}"; do
    NODE_IP=${GPU_NODES[$i]}
    NODE_NAME=${NODE_NAMES[$i]}
    
    echo ""
    echo "🔍 $NODE_NAME ($NODE_IP) の状況確認:"
    
    # NVIDIAドライバー確認（複数のコマンドを試行）
    driver_check=$(ssh jaist-lab@$NODE_IP "
        # まずnvidia-smiの存在確認
        if command -v nvidia-smi &> /dev/null; then
            # nvidia-smi --version を試行（新しいバージョン用）
            if nvidia-smi --version 2>/dev/null; then
                exit 0
            # nvidia-smi -q を試行（古いバージョン用）
            elif nvidia-smi -q 2>/dev/null | head -1; then
                exit 0
            # 単純にnvidia-smiを実行（最終手段）
            elif nvidia-smi 2>/dev/null | head -1; then
                exit 0
            fi
        fi
        echo 'NO_DRIVER'
    ")
    
    if [[ "$driver_check" == *"NO_DRIVER"* ]]; then
        echo -e "  ${YELLOW}⚠️  NVIDIAドライバー未検出 - 準備が必要${NC}"
        need_preparation=true
    else
        echo -e "  ${GREEN}✅ NVIDIAドライバー検出済み${NC}"
        # ドライバー情報を表示（デバッグ用）
        driver_version=$(ssh jaist-lab@$NODE_IP "
            if nvidia-smi --version 2>/dev/null; then
                nvidia-smi --version | grep 'NVIDIA-SMI version' || nvidia-smi --version | head -1
            else
                nvidia-smi 2>/dev/null | grep 'Driver Version' | awk '{print \$3}' || echo '(バージョン情報取得不可)'
            fi
        ")
        echo -e "     ドライバー: ${driver_version}"
    fi
    
    # カーネルヘッダー確認
    kernel_headers=$(ssh jaist-lab@$NODE_IP "dpkg -l | grep linux-headers-\$(uname -r) || echo 'NO_HEADERS'")
    if [[ "$kernel_headers" == *"NO_HEADERS"* ]]; then
        echo -e "  ${YELLOW}⚠️  カーネルヘッダー未インストール - 準備が必要${NC}"
        need_preparation=true
    else
        echo -e "  ${GREEN}✅ カーネルヘッダー確認済み${NC}"
    fi
    
    # containerd確認
    containerd_status=$(ssh jaist-lab@$NODE_IP "systemctl is-active containerd 2>/dev/null || echo 'INACTIVE'")
    if [[ "$containerd_status" != "active" ]]; then
        echo -e "  ${RED}❌ containerd未稼働 - 要確認${NC}"
        need_preparation=true
    else
        echo -e "  ${GREEN}✅ containerd稼働中${NC}"
    fi
done

if [ "$need_preparation" = true ]; then
    echo ""
    echo -e "${YELLOW}🔧 ${ENV_NAME}環境のGPUノード準備を実行します...${NC}"
    
    # GPUノード準備実行
    for i in "${!GPU_NODES[@]}"; do
        NODE_IP=${GPU_NODES[$i]}
        NODE_NAME=${NODE_NAMES[$i]}
        
        echo ""
        echo "🔧 $NODE_NAME ($NODE_IP) の準備実行:"
        
        # カーネルヘッダーのインストール
        echo "  - カーネルヘッダー確認・インストール..."
        ssh jaist-lab@$NODE_IP "
            if ! dpkg -l | grep -q linux-headers-\$(uname -r); then
                echo '    カーネルヘッダーをインストール中...'
                sudo apt update
                sudo apt install -y linux-headers-\$(uname -r)
            else
                echo '    カーネルヘッダー: インストール済み'
            fi
        "
        
        # 必要なパッケージのインストール
        echo "  - 必要パッケージ確認・インストール..."
        ssh jaist-lab@$NODE_IP "
            if ! dpkg -l | grep -q build-essential; then
                echo '    build-essentialをインストール中...'
                sudo apt install -y build-essential
            else
                echo '    build-essential: インストール済み'
            fi
        "
        
        # 監視ポート開放
        echo "  - 監視ポート開放..."
        ssh jaist-lab@$NODE_IP "
            # UFWでDCGM Exporterポート開放
            sudo ufw allow 9400/tcp
            echo '    DCGMポート9400開放完了'
        " 2>/dev/null || echo "    ポート設定スキップ"
        
        # containerdランタイム確認
        echo "  - containerdランタイム確認..."
        ssh jaist-lab@$NODE_IP "
            if systemctl is-active --quiet containerd; then
                echo '    containerd: 動作中'
            else
                echo '    エラー: containerdが動作していません'
                sudo systemctl start containerd
                sudo systemctl enable containerd
            fi
        "
        
        echo -e "  ${GREEN}✅ $NODE_NAME の準備完了${NC}"
    done
    
    echo ""
    echo -e "${GREEN}✅ ${ENV_NAME}環境のGPUノード準備完了${NC}"
else
    echo ""
    echo -e "${GREEN}✅ ${ENV_NAME}環境のGPUノード準備は不要です（環境は既に整っています）${NC}"
fi

echo ""
echo "=========================================="
echo "準備完了サマリー"
echo "=========================================="
echo "環境: ${ENV_NAME}"
echo "対象ノード数: ${#NODE_NAMES[@]}"
echo "ノード: ${NODE_NAMES[@]}"
echo "=========================================="