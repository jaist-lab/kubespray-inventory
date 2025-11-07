# GPUノード準備スクリプト（条件付き実行）

echo "🔧 GPUノード準備確認"
echo "=================="

GPU_NODES=("172.16.100.31" "172.16.100.32")
NODE_NAMES=("dlcsv1" "dlcsv2")

# 準備が必要かどうかを確認
need_preparation=false

for i in "${!GPU_NODES[@]}"; do
    NODE_IP=${GPU_NODES[$i]}
    NODE_NAME=${NODE_NAMES[$i]}
    
    echo ""
    echo "🔍 $NODE_NAME ($NODE_IP) の状況確認:"
    
    # NVIDIAドライバー確認
    driver_check=$(ssh jaist-lab@$NODE_IP "nvidia-smi --version 2>/dev/null || echo 'NO_DRIVER'")
    if [[ "$driver_check" == *"NO_DRIVER"* ]]; then
        echo "  ⚠️ NVIDIAドライバー未検出 - 準備が必要"
        need_preparation=true
    else
        echo "  ✅ NVIDIAドライバー検出済み"
    fi
    
    # カーネルヘッダー確認
    kernel_headers=$(ssh jaist-lab@$NODE_IP "dpkg -l | grep linux-headers-\$(uname -r) || echo 'NO_HEADERS'")
    if [[ "$kernel_headers" == *"NO_HEADERS"* ]]; then
        echo "  ⚠️ カーネルヘッダー未インストール - 準備が必要"
        need_preparation=true
    else
        echo "  ✅ カーネルヘッダー確認済み"
    fi
    
    # containerd確認
    containerd_status=$(ssh jaist-lab@$NODE_IP "systemctl is-active containerd 2>/dev/null || echo 'INACTIVE'")
    if [[ "$containerd_status" != "active" ]]; then
        echo "  ❌ containerd未稼働 - 要確認"
        need_preparation=true
    else
        echo "  ✅ containerd稼働中"
    fi
done

if [ "$need_preparation" = true ]; then
    echo ""
    echo "🔧 GPUノード準備を実行します..."
    
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
        
        # 🔧 NEW: 監視ポート開放
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
    done
    
    echo ""
    echo "✅ GPUノード準備完了"
else
    echo ""
    echo "✅ GPUノード準備は不要です（環境は既に整っています）"
fi
