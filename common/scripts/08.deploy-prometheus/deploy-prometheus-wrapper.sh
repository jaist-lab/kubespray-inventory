#!/bin/bash

#==============================================================================
# Prometheus Stack Deployment Wrapper Script (Fixed Version)
# r760xs1からSSH経由でCeph情報を取得してデプロイメントスクリプトを実行
# 修正内容:
#   - デプロイスクリプト名を deploy-prometheus.sh に変更
#   - StorageClass再作成オプションの説明を改善
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
    -H, --ceph-host HOST     Cephホスト (デフォルト: r760xs1)
    -u, --ceph-user USER     Ceph SSH接続ユーザー (デフォルト: root)
    -p, --ceph-port PORT     Ceph SSH接続ポート (デフォルト: 22)
    --skip-ceph             Ceph CSI Driverのデプロイをスキップ
    --recreate-sc           既存のStorageClassを削除して再作成
    --dry-run               実際のデプロイを行わず、設定のみ表示
    -h, --help              このヘルプを表示

Ceph情報はr760xs1からSSH経由で自動取得されます:
    - CephクラスタID: ssh r760xs1 'ceph fsid'
    - Cephモニター: ssh r760xs1 'ceph mon dump'
    - Cephプール: kubernetes (存在しない場合は自動作成)
    - Ceph認証キー: ssh r760xs1 'ceph auth get-or-create client.kubernetes ...'
      (client.kubernetesユーザーが存在しない場合は自動作成)

SSH接続設定:
    ~/.ssh/config に以下の設定を推奨:
    Host r760xs1
        HostName 172.16.200.11
        User root
        IdentityFile ~/.ssh/id_rsa

例:
    $0 -e production
    $0 -e development --dry-run
    $0 -e sandbox -H r760xs1 -u root
    $0 -e production --recreate-sc    # StorageClassを再作成

修正内容:
    - StorageClass作成ロジックの改善（Helmではなく手動作成に統一）
    - デプロイスクリプト: deploy-prometheus.sh

EOF
    exit 1
}

# デフォルト値
ENVIRONMENT=""
CEPH_HOST="r760xs1"
CEPH_USER="root"
CEPH_PORT="22"
SKIP_CEPH=false
DRY_RUN=false
RECREATE_SC=false
DEPLOY_SCRIPT="./deploy-prometheus.sh"
CEPH_POOL="kubernetes"

# 引数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -H|--ceph-host)
            CEPH_HOST="$2"
            shift 2
            ;;
        -u|--ceph-user)
            CEPH_USER="$2"
            shift 2
            ;;
        -p|--ceph-port)
            CEPH_PORT="$2"
            shift 2
            ;;
        --skip-ceph)
            SKIP_CEPH=true
            shift
            ;;
        --recreate-sc)
            RECREATE_SC=true
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
    log_error "deploy-prometheus.sh が同じディレクトリに存在することを確認してください"
    exit 1
fi

log_info "=========================================="
log_info "Prometheus Stack デプロイ - 環境情報取得"
log_info "=========================================="
log_info "環境: $ENVIRONMENT"
log_info "Cephホスト: ${CEPH_USER}@${CEPH_HOST}:${CEPH_PORT}"
log_info "デプロイスクリプト: $DEPLOY_SCRIPT"

#==============================================================================
# SSH接続確認
#==============================================================================
if [[ "$SKIP_CEPH" == false ]]; then
    log_info "SSH接続確認中: ${CEPH_USER}@${CEPH_HOST}"
    if ! ssh -p "$CEPH_PORT" -o ConnectTimeout=10 -o BatchMode=yes "${CEPH_USER}@${CEPH_HOST}" "exit" 2>/dev/null; then
        log_error "SSH接続に失敗しました: ${CEPH_USER}@${CEPH_HOST}:${CEPH_PORT}"
        log_error ""
        log_error "以下を確認してください:"
        log_error "  1. SSHキーが設定されているか"
        log_error "  2. ~/.ssh/config に以下の設定があるか:"
        log_error "     Host r760xs1"
        log_error "         HostName 172.16.200.11"
        log_error "         User root"
        log_error "         IdentityFile ~/.ssh/id_rsa"
        log_error "  3. ホストに到達可能か: ping ${CEPH_HOST}"
        exit 1
    fi
    log_success "SSH接続OK"
fi

#==============================================================================
# Ceph情報取得
#==============================================================================
if [[ "$SKIP_CEPH" == false ]]; then
    log_info "Ceph情報をSSH経由で取得中..."
    
    # 1. CephクラスタIDを取得
    log_info "CephクラスタIDを取得中..."
    CEPH_CLUSTER_ID=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "ceph fsid 2>/dev/null" | tr -d '[:space:]')
    
    if [[ -z "$CEPH_CLUSTER_ID" ]]; then
        log_error "CephクラスタIDを取得できませんでした"
        log_error "リモートホストでcephコマンドが正常に動作するか確認してください:"
        log_error "  ssh ${CEPH_USER}@${CEPH_HOST} 'ceph fsid'"
        exit 1
    fi
    log_success "クラスタID取得成功: $CEPH_CLUSTER_ID"
    
    # 2. Cephモニターアドレスを取得
    log_info "Cephモニターアドレスを取得中..."
    CEPH_MONITORS_RAW=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "ceph mon dump 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+:\d+'" | paste -sd ',' -)
    
    if [[ -z "$CEPH_MONITORS_RAW" ]]; then
        log_warn "ceph mon dumpでモニターアドレスを取得できませんでした"
        log_info "ceph.confから取得を試みます..."
        
        CEPH_MONITORS=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "grep -oP 'mon_host\s*=\s*\K.*' /etc/ceph/ceph.conf 2>/dev/null" | tr -d '[:space:]')
        
        if [[ -z "$CEPH_MONITORS" ]]; then
            log_error "Cephモニターアドレスを取得できませんでした"
            log_error "リモートホストで以下を確認してください:"
            log_error "  ssh ${CEPH_USER}@${CEPH_HOST} 'ceph mon dump'"
            log_error "  ssh ${CEPH_USER}@${CEPH_HOST} 'cat /etc/ceph/ceph.conf'"
            exit 1
        fi
        log_success "ceph.confからモニターアドレス取得: $CEPH_MONITORS"
    else
        CEPH_MONITORS="$CEPH_MONITORS_RAW"
        log_success "モニターアドレス取得成功: $CEPH_MONITORS"
    fi
    
    # 3. Cephプール存在確認と作成
    log_info "Cephプール '${CEPH_POOL}' の存在確認中..."
    if ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "ceph osd pool ls 2>/dev/null | grep -q '^${CEPH_POOL}$'"; then
        log_success "Cephプール '${CEPH_POOL}' が存在します"
    else
        log_warn "Cephプール '${CEPH_POOL}' が存在しません"
        log_info "プールを作成します..."
        
        # プール作成
        if ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "ceph osd pool create ${CEPH_POOL} 128 128 2>/dev/null"; then
            log_success "Cephプール '${CEPH_POOL}' を作成しました"
            
            # RBDアプリケーション有効化
            if ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "ceph osd pool application enable ${CEPH_POOL} rbd 2>/dev/null"; then
                log_success "プール '${CEPH_POOL}' にRBDアプリケーションを有効化しました"
            else
                log_warn "RBDアプリケーションの有効化に失敗しました（既に有効の可能性あり）"
            fi
        else
            log_error "Cephプール '${CEPH_POOL}' の作成に失敗しました"
            log_error "手動で作成してください:"
            log_error "  ssh ${CEPH_USER}@${CEPH_HOST} 'ceph osd pool create ${CEPH_POOL} 128 128'"
            log_error "  ssh ${CEPH_USER}@${CEPH_HOST} 'ceph osd pool application enable ${CEPH_POOL} rbd'"
            exit 1
        fi
    fi
    
    # 4. Ceph認証キーを取得（get-or-createで自動作成）
    log_info "Ceph認証情報を取得/作成中 (client.kubernetes)..."
    
    CEPH_AUTH_OUTPUT=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" \
        "ceph auth get-or-create client.kubernetes \
        mon 'allow r' \
        osd 'allow class-read object_prefix rbd_children, allow rwx pool=${CEPH_POOL}' 2>/dev/null")
    
    if [[ -z "$CEPH_AUTH_OUTPUT" ]]; then
        log_error "Ceph認証情報の取得/作成に失敗しました"
        log_error "リモートホストで以下を確認してください:"
        log_error "  ssh ${CEPH_USER}@${CEPH_HOST} 'ceph auth get-or-create client.kubernetes mon \"allow r\" osd \"allow class-read object_prefix rbd_children, allow rwx pool=${CEPH_POOL}\"'"
        exit 1
    fi
    
    # 認証キーの抽出
    CEPH_KEY=$(echo "$CEPH_AUTH_OUTPUT" | grep -oP 'key\s*=\s*\K[A-Za-z0-9+/=]+' | head -n1 | tr -d '[:space:]')
    
    if [[ -z "$CEPH_KEY" ]]; then
        log_error "認証キーの抽出に失敗しました"
        log_error "ceph auth get-or-create の出力:"
        log_error "$CEPH_AUTH_OUTPUT"
        exit 1
    fi
    
    # 認証キーの妥当性チェック（Base64形式か）
    if [[ ! "$CEPH_KEY" =~ ^[A-Za-z0-9+/]+=*$ ]]; then
        log_error "取得した認証キーが不正な形式です: ${CEPH_KEY:0:20}..."
        exit 1
    fi
    
    log_success "Ceph認証情報取得/作成完了 (client.kubernetes)"
    
    # Ceph情報サマリー
    log_info ""
    log_info "=========================================="
    log_info "取得したCeph情報"
    log_info "=========================================="
    log_info "取得元ホスト: ${CEPH_USER}@${CEPH_HOST}:${CEPH_PORT}"
    log_info "クラスタID: $CEPH_CLUSTER_ID"
    log_info "モニター: $CEPH_MONITORS"
    log_info "プール: $CEPH_POOL"
    log_info "ユーザー: client.kubernetes"
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
    DEPLOY_ARGS+=("-p" "$CEPH_POOL")
else
    DEPLOY_ARGS+=("--skip-ceph")
fi

if [[ "$RECREATE_SC" == true ]]; then
    DEPLOY_ARGS+=("--recreate-sc")
fi

if [[ "$DRY_RUN" == true ]]; then
    DEPLOY_ARGS+=("--dry-run")
fi

log_info "実行コマンド: $DEPLOY_SCRIPT ${DEPLOY_ARGS[*]}"
log_info ""

# スクリプト実行
bash "$DEPLOY_SCRIPT" "${DEPLOY_ARGS[@]}"

EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    log_success ""
    log_success "=========================================="
    log_success "全デプロイメント完了!"
    log_success "=========================================="
    log_info ""
    log_info "Ceph認証情報が保存されました:"
    log_info "  ユーザー: client.kubernetes"
    log_info "  権限: mon 'allow r', osd 'allow class-read object_prefix rbd_children, allow rwx pool=${CEPH_POOL}'"
    log_info ""
    log_info "認証情報を確認するには:"
    log_info "  ssh ${CEPH_USER}@${CEPH_HOST} 'ceph auth get client.kubernetes'"
else
    log_error ""
    log_error "=========================================="
    log_error "デプロイメントに失敗しました"
    log_error "=========================================="
fi

exit $EXIT_CODE