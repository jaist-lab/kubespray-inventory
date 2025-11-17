#!/bin/bash
# etcdデフラグメンテーションスクリプト
# 使用方法: ./defrag-etcd.sh {production|development|sandbox|all}

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 環境設定
declare -A ENVIRONMENTS=(
    ["production"]="172.16.200.101:2379,172.16.200.102:2379,172.16.200.103:2379"
    ["development"]="172.16.200.121:2379,172.16.200.122:2379,172.16.200.123:2379"
    ["sandbox"]="172.16.200.131:2379,172.16.200.132:2379,172.16.200.133:2379"
)

declare -A NODES=(
    ["production"]="master01 master02 master03"
    ["development"]="dev-master01 dev-master02 dev-master03"
    ["sandbox"]="sandbox-master01 sandbox-master02 sandbox-master03"
)

# ノード間の待機時間（秒）
WAIT_TIME=300  # 5分

# 使用方法表示
usage() {
    echo "使用方法: $0 {production|development|sandbox|all} [options]"
    echo ""
    echo "オプション:"
    echo "  --wait N      ノード間の待機時間を指定（秒、デフォルト: 300）"
    echo "  --status      デフラグ前後のステータスを表示"
    echo "  --yes         確認プロンプトをスキップ"
    echo ""
    echo "例:"
    echo "  $0 production --status"
    echo "  $0 sandbox --wait 180"
    echo "  $0 all --yes"
    echo ""
    echo "⚠️  警告: デフラグメンテーションは各ノードで順番に実行されます。"
    echo "          クラスタ全体で最大15分程度かかる可能性があります。"
    exit 1
}

# デフラグ前のステータス表示
show_status_before() {
    local ENV=$1
    local ENDPOINTS=${ENVIRONMENTS[$ENV]}
    local NODES_ARRAY=(${NODES[$ENV]})
    local FIRST_NODE=${NODES_ARRAY[0]}
    
    echo -e "${BLUE}=== デフラグ前のステータス ===${NC}"
    ssh $FIRST_NODE "ETCDCTL_API=3 sudo etcdctl \
        --endpoints=https://$ENDPOINTS \
        --cacert=/etc/ssl/etcd/ssl/ca.pem \
        --cert=/etc/ssl/etcd/ssl/node-$FIRST_NODE.pem \
        --key=/etc/ssl/etcd/ssl/node-$FIRST_NODE-key.pem \
        endpoint status -w table"
    echo ""
}

# デフラグ後のステータス表示
show_status_after() {
    local ENV=$1
    local ENDPOINTS=${ENVIRONMENTS[$ENV]}
    local NODES_ARRAY=(${NODES[$ENV]})
    local FIRST_NODE=${NODES_ARRAY[0]}
    
    echo -e "${BLUE}=== デフラグ後のステータス ===${NC}"
    ssh $FIRST_NODE "ETCDCTL_API=3 sudo etcdctl \
        --endpoints=https://$ENDPOINTS \
        --cacert=/etc/ssl/etcd/ssl/ca.pem \
        --cert=/etc/ssl/etcd/ssl/node-$FIRST_NODE.pem \
        --key=/etc/ssl/etcd/ssl/node-$FIRST_NODE-key.pem \
        endpoint status -w table"
    echo ""
}

# 単一ノードのデフラグ実行
defrag_node() {
    local NODE=$1
    local NODE_IP=$2
    
    echo -e "${YELLOW}--- $NODE のデフラグメンテーション開始 ---${NC}"
    echo "エンドポイント: https://$NODE_IP:2379"
    echo "開始時刻: $(date '+%Y-%m-%d %H:%M:%S')"
    
    local START_TIME=$(date +%s)
    
    # デフラグ実行
    if ssh $NODE "ETCDCTL_API=3 sudo etcdctl \
        --endpoints=https://$NODE_IP:2379 \
        --cacert=/etc/ssl/etcd/ssl/ca.pem \
        --cert=/etc/ssl/etcd/ssl/node-$NODE.pem \
        --key=/etc/ssl/etcd/ssl/node-$NODE-key.pem \
        defrag" 2>&1; then
        
        local END_TIME=$(date +%s)
        local DURATION=$((END_TIME - START_TIME))
        
        echo -e "${GREEN}✓ $NODE のデフラグメンテーション完了（所要時間: ${DURATION}秒）${NC}"
        return 0
    else
        echo -e "${RED}✗ $NODE のデフラグメンテーション失敗${NC}"
        return 1
    fi
}

# 環境全体のデフラグ実行
defrag_environment() {
    local ENV=$1
    local SHOW_STATUS=$2
    local NODES_ARRAY=(${NODES[$ENV]})
    
    # IPアドレスの配列を作成
    local IPS=(${ENVIRONMENTS[$ENV]//,/ })
    local IP_ARRAY=()
    for ip in "${IPS[@]}"; do
        IP_ARRAY+=("${ip%:2379}")
    done
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ${ENV^^} Environment - Defragmentation                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # デフラグ前のステータス表示
    if [ "$SHOW_STATUS" = true ]; then
        show_status_before "$ENV"
    fi
    
    local TOTAL=${#NODES_ARRAY[@]}
    local SUCCEEDED=0
    local FAILED=0
    
    # 各ノードで順番にデフラグ実行
    for i in "${!NODES_ARRAY[@]}"; do
        local NODE=${NODES_ARRAY[$i]}
        local NODE_IP=${IP_ARRAY[$i]}
        
        if defrag_node "$NODE" "$NODE_IP"; then
            SUCCEEDED=$((SUCCEEDED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
        
        # 最後のノード以外は待機
        if [ $i -lt $((TOTAL - 1)) ]; then
            echo ""
            echo -e "${BLUE}次のノードまで ${WAIT_TIME}秒 待機中...${NC}"
            echo "（クラスタの安定化のため）"
            sleep $WAIT_TIME
            echo ""
        fi
    done
    
    echo ""
    echo -e "${BLUE}=== $ENV環境: デフラグメンテーション完了 ===${NC}"
    echo -e "総ノード数: $TOTAL"
    echo -e "${GREEN}成功: $SUCCEEDED${NC}"
    if [ $FAILED -gt 0 ]; then
        echo -e "${RED}失敗: $FAILED${NC}"
    fi
    echo ""
    
    # デフラグ後のステータス表示
    if [ "$SHOW_STATUS" = true ]; then
        sleep 10  # 少し待ってからステータス表示
        show_status_after "$ENV"
    fi
}

# 確認プロンプト
confirm_execution() {
    local ENV=$1
    
    echo -e "${YELLOW}⚠️  警告${NC}"
    echo "これから ${ENV} 環境のetcdデフラグメンテーションを実行します。"
    echo ""
    echo "実行内容:"
    echo "  - 各ノードで順番にデフラグメンテーションを実行"
    echo "  - ノード間の待機時間: ${WAIT_TIME}秒"
    echo "  - 推定所要時間: $((WAIT_TIME * 2 / 60))分程度"
    echo ""
    echo "この操作中、etcdのパフォーマンスが一時的に低下する可能性があります。"
    echo ""
    read -p "続行しますか? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "キャンセルしました。"
        exit 0
    fi
    echo ""
}

# メイン処理
main() {
    local ENV=$1
    local SHOW_STATUS=false
    local SKIP_CONFIRM=false
    
    # オプション解析
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --wait)
                WAIT_TIME=$2
                shift 2
                ;;
            --status)
                SHOW_STATUS=true
                shift
                ;;
            --yes)
                SKIP_CONFIRM=true
                shift
                ;;
            *)
                echo "不明なオプション: $1"
                usage
                ;;
        esac
    done
    
    # 環境の検証
    if [ "$ENV" != "production" ] && [ "$ENV" != "development" ] && [ "$ENV" != "sandbox" ] && [ "$ENV" != "all" ]; then
        usage
    fi
    
    # 処理対象の環境リスト
    local ENVS=()
    if [ "$ENV" == "all" ]; then
        ENVS=("production" "development" "sandbox")
    else
        ENVS=("$ENV")
    fi
    
    # 確認プロンプト
    if [ "$SKIP_CONFIRM" != true ]; then
        if [ "$ENV" == "all" ]; then
            confirm_execution "全環境 (production, development, sandbox)"
        else
            confirm_execution "$ENV"
        fi
    fi
    
    # 開始時刻記録
    local SCRIPT_START=$(date +%s)
    
    # 各環境で処理実行
    for env in "${ENVS[@]}"; do
        defrag_environment "$env" "$SHOW_STATUS"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # 複数環境の場合、環境間でも待機
        if [ "${#ENVS[@]}" -gt 1 ] && [ "$env" != "${ENVS[-1]}" ]; then
            echo -e "${BLUE}次の環境まで 60秒 待機中...${NC}"
            sleep 60
            echo ""
        fi
    done
    
    # 終了時刻と所要時間
    local SCRIPT_END=$(date +%s)
    local TOTAL_DURATION=$((SCRIPT_END - SCRIPT_START))
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  すべてのデフラグメンテーションが完了しました          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "総所要時間: $((TOTAL_DURATION / 60))分 $((TOTAL_DURATION % 60))秒"
    echo ""
    echo "次のステップ:"
    echo "  1. パフォーマンステストを再実行してください"
    echo "     ./check-etcd-perf.sh ${ENV}"
    echo ""
    echo "  2. Kubernetesクラスタの状態を確認してください"
    echo "     kubectl get nodes"
    echo "     kubectl get pods -A"
}

# 引数チェック
if [ $# -lt 1 ]; then
    usage
fi

# スクリプト実行
main "$@"
