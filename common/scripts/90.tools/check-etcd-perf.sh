#!/bin/bash
# etcdパフォーマンスチェックスクリプト
# 使用方法: ./check-etcd-perf.sh {production|development|sandbox|all}

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
    ["development"]="172.16.200.111:2379,172.16.200.112:2379,172.16.200.113:2379"
    ["sandbox"]="172.16.200.131:2379,172.16.200.132:2379,172.16.200.133:2379"
)

declare -A NODES=(
    ["production"]="master01 master02 master03"
    ["development"]="dev-master01 dev-master02 dev-master03"
    ["sandbox"]="sandbox-master01 sandbox-master02 sandbox-master03"
)

# 使用方法表示
usage() {
    echo "使用方法: $0 {production|development|sandbox|all} [options]"
    echo ""
    echo "オプション:"
    echo "  --cleanup     テスト前に古いテストデータを削除"
    echo "  --health      パフォーマンステストの代わりにヘルスチェックのみ実行"
    echo "  --status      ステータス情報のみ表示"
    echo ""
    echo "例:"
    echo "  $0 production"
    echo "  $0 sandbox --cleanup"
    echo "  $0 all --health"
    exit 1
}

# テストデータクリーンアップ
cleanup_test_data() {
    local ENV=$1
    local ENDPOINTS=${ENVIRONMENTS[$ENV]}
    local NODES_ARRAY=(${NODES[$ENV]})
    local FIRST_NODE=${NODES_ARRAY[0]}
    
    echo -e "${YELLOW}=== $ENV環境: テストデータクリーンアップ ===${NC}"
    
    ssh $FIRST_NODE "ETCDCTL_API=3 sudo etcdctl \
        --endpoints=https://${ENDPOINTS%%,*} \
        --cacert=/etc/ssl/etcd/ssl/ca.pem \
        --cert=/etc/ssl/etcd/ssl/node-$FIRST_NODE.pem \
        --key=/etc/ssl/etcd/ssl/node-$FIRST_NODE-key.pem \
        del --prefix /etcdctl-check-perf/" 2>&1 | grep -v "^0$" || echo "クリーンアップ完了"
    echo ""
}

# ヘルスチェック
check_health() {
    local ENV=$1
    local ENDPOINTS=${ENVIRONMENTS[$ENV]}
    local NODES_ARRAY=(${NODES[$ENV]})
    local FIRST_NODE=${NODES_ARRAY[0]}
    
    echo -e "${BLUE}=== $ENV環境: ヘルスチェック ===${NC}"
    
    ssh $FIRST_NODE "ETCDCTL_API=3 sudo etcdctl \
        --endpoints=https://$ENDPOINTS \
        --cacert=/etc/ssl/etcd/ssl/ca.pem \
        --cert=/etc/ssl/etcd/ssl/node-$FIRST_NODE.pem \
        --key=/etc/ssl/etcd/ssl/node-$FIRST_NODE-key.pem \
        endpoint health -w table"
    echo ""
}

# ステータス確認
check_status() {
    local ENV=$1
    local ENDPOINTS=${ENVIRONMENTS[$ENV]}
    local NODES_ARRAY=(${NODES[$ENV]})
    local FIRST_NODE=${NODES_ARRAY[0]}
    
    echo -e "${BLUE}=== $ENV環境: ステータス ===${NC}"
    
    ssh $FIRST_NODE "ETCDCTL_API=3 sudo etcdctl \
        --endpoints=https://$ENDPOINTS \
        --cacert=/etc/ssl/etcd/ssl/ca.pem \
        --cert=/etc/ssl/etcd/ssl/node-$FIRST_NODE.pem \
        --key=/etc/ssl/etcd/ssl/node-$FIRST_NODE-key.pem \
        endpoint status -w table"
    echo ""
}

# パフォーマンステスト
check_performance() {
    local ENV=$1
    local ENDPOINTS=${ENVIRONMENTS[$ENV]}
    local NODES_ARRAY=(${NODES[$ENV]})
    
    echo -e "${BLUE}=== $ENV環境: パフォーマンステスト ===${NC}"
    
    local TOTAL=0
    local PASSED=0
    local FAILED=0
    
    for node in ${NODES_ARRAY[@]}; do
        echo -e "${YELLOW}--- $node ---${NC}"
        
        # パフォーマンステスト実行
        local OUTPUT=$(ssh $node "ETCDCTL_API=3 sudo etcdctl \
            --endpoints=https://$ENDPOINTS \
            --cacert=/etc/ssl/etcd/ssl/ca.pem \
            --cert=/etc/ssl/etcd/ssl/node-$node.pem \
            --key=/etc/ssl/etcd/ssl/node-$node-key.pem \
            check perf" 2>&1)
        
        # 結果を表示（最後の5行）
        echo "$OUTPUT" | tail -5
        
        # 結果を集計
        TOTAL=$((TOTAL + 1))
        if echo "$OUTPUT" | grep -q "^PASS$"; then
            PASSED=$((PASSED + 1))
            echo -e "${GREEN}✓ PASS${NC}"
        else
            FAILED=$((FAILED + 1))
            echo -e "${RED}✗ FAIL${NC}"
        fi
        echo ""
    done
    
    # サマリー表示
    echo -e "${BLUE}=== $ENV環境: サマリー ===${NC}"
    echo -e "総ノード数: $TOTAL"
    echo -e "${GREEN}PASS: $PASSED${NC}"
    echo -e "${RED}FAIL: $FAILED${NC}"
    echo ""
}

# メイン処理
main() {
    local ENV=$1
    local DO_CLEANUP=false
    local HEALTH_ONLY=false
    local STATUS_ONLY=false
    
    # オプション解析
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup)
                DO_CLEANUP=true
                shift
                ;;
            --health)
                HEALTH_ONLY=true
                shift
                ;;
            --status)
                STATUS_ONLY=true
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
    
    # 各環境で処理実行
    for env in "${ENVS[@]}"; do
        echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ${env^^} Environment                                    ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # クリーンアップ（オプション）
        if [ "$DO_CLEANUP" = true ]; then
            cleanup_test_data "$env"
        fi
        
        # ステータスのみ
        if [ "$STATUS_ONLY" = true ]; then
            check_status "$env"
            continue
        fi
        
        # ヘルスチェックのみ
        if [ "$HEALTH_ONLY" = true ]; then
            check_health "$env"
            check_status "$env"
            continue
        fi
        
        # フルチェック（デフォルト）
        check_health "$env"
        check_status "$env"
        check_performance "$env"
        
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    done
}

# 引数チェック
if [ $# -lt 1 ]; then
    usage
fi

# スクリプト実行
main "$@"
