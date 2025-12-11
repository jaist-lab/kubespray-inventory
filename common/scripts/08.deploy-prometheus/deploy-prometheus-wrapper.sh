#!/bin/bash

#==============================================================================
# Prometheus Stack Deployment Wrapper Script
# 環境に応じたCeph情報を自動取得してデプロイメントスクリプトを実行
#==============================================================================

set -e

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 使用方法
usage() {
    cat << EOF
使用方法: $0 [OPTIONS]

OPTIONS:
    -e, --environment ENV    環境を指定 (production|development|sandbox) [必須]
    --skip-ceph             Ceph CSI Driverのデプロイをスキップ
    --dry-run               実際のデプロイを行わず、設定のみ表示
    -h, --help              このヘルプを表示

Ceph情報は以下から自動取得されます:
    - Cephクラスタに'ceph fsid'コマンドで接続してクラスタIDを取得
    - 環境変数 CEPH_KUBERNETES_KEY からCeph認証キーを取得
    - または /etc/ceph/ceph.client.kubernetes.keyring から取得

環境変数の設定例:
    export CEPH_KUBERNETES_KEY="AQDxxxxxxxxxxxxx=="
    
    または keyringファイルを配置:
    /etc/ceph/ceph.client.kubernetes.keyring

例:
    $0 -e production
    $0 -e development --dry-run
    CEPH_KUBERNETES_KEY="AQDxxx==" $0 -e sandbox

EOF
    exit 1
}

# デフォルト値
ENVIRONMENT=""
SKIP_CEPH=false
DRY_RUN=false
DEPLOY_SCRIPT="${HOME}/kubernetes/deploy-prometheus.sh"
CEPH_CONFIG="/etc/ceph/ceph.conf"
CEPH_KEYRING_PATH="/etc/ceph/ceph.client.kubernetes.keyring"

# 引数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --skip-ceph)
            SKIP_CEPH=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "不明なオプション: $1"
            usage
            ;;
    esac
done

# 必須パラメータチェック
if [[ -z "$ENVIRONMENT" ]]; then
    log_error "環境が指定されていません"
    usage
fi

if [[ ! "$ENVIRONMENT" =~ ^(production|development|sandbox)$ ]]; then
    log_error "無効な環境: $ENVIRONMENT"
    exit 1
fi

# デプロイスクリプト存在確認
if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    log_error "デプロイスクリプトが見つかりません: $DEPLOY_SCRIPT"
    exit 1
fi

log_info "=========================================="
log_info "Prometheus Stack デプロイ - 環境情報取得"
log_info "=========================================="
log_info "環境: $ENVIRONMENT"

#==============================================================================
# Ceph情報取得
#==============================================================================
if [[ "$SKIP_CEPH" == false ]]; then
    log_info "Ceph情報を取得中..."
    
    # 1. CephクラスタIDを取得
    log_info "CephクラスタIDを取得中..."
    if command -v ceph &> /dev/null && [[ -f "$CEPH_CONFIG" ]]; then
        CEPH_CLUSTER_ID=$(ceph fsid 2>/dev/null | tr -d '[:space:]')
        if [[ -z "$CEPH_CLUSTER_ID" ]]; then
            log_warn "cephコマンドでクラスタIDを取得できませんでした"
            log_warn "デフォルト値を使用します"
            CEPH_CLUSTER_ID="6ba61fd6-e71f-4a4c-8dc8-9ad3af1bd1f4"
        else
            log_success "クラスタID取得成功: $CEPH_CLUSTER_ID"
        fi
    else
        log_warn "cephコマンドまたは設定ファイルが見つかりません"
        log_warn "デフォルト値を使用します"
        CEPH_CLUSTER_ID="6ba61fd6-e71f-4a4c-8dc8-9ad3af1bd1f4"
    fi
    
    # 2. Cephモニターアドレスを取得
    log_info "Cephモニターアドレスを取得中..."
    if command -v ceph &> /dev/null && [[ -f "$CEPH_CONFIG" ]]; then
        # ceph mon dumpから取得を試みる
        CEPH_MONITORS_RAW=$(ceph mon dump 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+:\d+' | paste -sd ',' -)
        if [[ -n "$CEPH_MONITORS_RAW" ]]; then
            CEPH_MONITORS="$CEPH_MONITORS_RAW"
            log_success "モニターアドレス取得成功: $CEPH_MONITORS"
        else
            log_warn "cephコマンドでモニターアドレスを取得できませんでした"
            # ceph.confから取得を試みる
            if [[ -f "$CEPH_CONFIG" ]]; then
                CEPH_MONITORS=$(grep -oP 'mon_host\s*=\s*\K.*' "$CEPH_CONFIG" | tr -d '[:space:]')
                if [[ -n "$CEPH_MONITORS" ]]; then
                    log_success "ceph.confからモニターアドレス取得: $CEPH_MONITORS"
                else
                    log_warn "デフォルト値を使用します"
                    CEPH_MONITORS="172.16.200.11:6789,172.16.200.12:6789,172.16.200.13:6789,172.16.200.14:6789,172.16.200.15:6789"
                fi
            else
                log_warn "デフォルト値を使用します"
                CEPH_MONITORS="172.16.200.11:6789,172.16.200.12:6789,172.16.200.13:6789,172.16.200.14:6789,172.16.200.15:6789"
            fi
        fi
    else
        log_warn "デフォルト値を使用します"
        CEPH_MONITORS="172.16.200.11:6789,172.16.200.12:6789,172.16.200.13:6789,172.16.200.14:6789,172.16.200.15:6789"
    fi
    
    # 3. Ceph認証キーを取得
    log_info "Ceph認証キーを取得中..."
    CEPH_KEY=""
    
    # 環境変数から取得
    if [[ -n "$CEPH_KUBERNETES_KEY" ]]; then
        CEPH_KEY="$CEPH_KUBERNETES_KEY"
        log_success "環境変数からCeph認証キーを取得しました"
    # keyringファイルから取得
    elif [[ -f "$CEPH_KEYRING_PATH" ]]; then
        CEPH_KEY=$(grep -oP 'key\s*=\s*\K.*' "$CEPH_KEYRING_PATH" | tr -d '[:space:]')
        if [[ -n "$CEPH_KEY" ]]; then
            log_success "keyringファイルからCeph認証キーを取得しました: $CEPH_KEYRING_PATH"
        else
            log_error "keyringファイルは存在しますが、キーが見つかりません"
            exit 1
        fi
    # ceph auth get-keyコマンドから取得
    elif command -v ceph &> /dev/null && [[ -f "$CEPH_CONFIG" ]]; then
        CEPH_KEY=$(ceph auth get-key client.kubernetes 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$CEPH_KEY" ]]; then
            log_success "cephコマンドからCeph認証キーを取得しました"
        else
            log_error "Ceph認証キーを取得できませんでした"
            log_error "以下のいずれかの方法で認証キーを設定してください:"
            log_error "  1. 環境変数: export CEPH_KUBERNETES_KEY=\"AQDxxxxx==\""
            log_error "  2. keyringファイル: $CEPH_KEYRING_PATH"
            exit 1
        fi
    else
        log_error "Ceph認証キーを取得できませんでした"
        log_error "以下のいずれかの方法で認証キーを設定してください:"
        log_error "  1. 環境変数: export CEPH_KUBERNETES_KEY=\"AQDxxxxx==\""
        log_error "  2. keyringファイル: $CEPH_KEYRING_PATH"
        exit 1
    fi
    
    # Ceph情報サマリー
    log_info ""
    log_info "=========================================="
    log_info "取得したCeph情報"
    log_info "=========================================="
    log_info "クラスタID: $CEPH_CLUSTER_ID"
    log_info "モニター: $CEPH_MONITORS"
    log_info "認証キー: ${CEPH_KEY:0:10}... (最初の10文字のみ表示)"
    log_info "=========================================="
    log_info ""
fi

#==============================================================================
# デプロイスクリプト実行
#==============================================================================
log_info "デプロイスクリプトを実行します..."

DEPLOY_ARGS=("-e" "$ENVIRONMENT")

if [[ "$SKIP_CEPH" == false ]]; then
    DEPLOY_ARGS+=("-c" "$CEPH_KEY")
    DEPLOY_ARGS+=("-i" "$CEPH_CLUSTER_ID")
    DEPLOY_ARGS+=("-m" "$CEPH_MONITORS")
else
    DEPLOY_ARGS+=("--skip-ceph")
fi

if [[ "$DRY_RUN" == true ]]; then
    DEPLOY_ARGS+=("--dry-run")
fi

log_info "実行コマンド: $DEPLOY_SCRIPT ${DEPLOY_ARGS[*]}"
log_info ""

# スクリプト実行
bash "$DEPLOY_SCRIPT" "${DEPLOY_ARGS[@]}"

exit $?