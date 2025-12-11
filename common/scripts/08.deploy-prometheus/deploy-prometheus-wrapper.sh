#!/bin/bash

#==============================================================================
# Prometheus Stack Deployment Wrapper Script
# r760xs1からSSH経由でCeph情報を取得してデプロイメントスクリプトを実行
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
    --dry-run               実際のデプロイを行わず、設定のみ表示
    -h, --help              このヘルプを表示

Ceph情報はr760xs1からSSH経由で自動取得されます:
    - CephクラスタID: ssh r760xs1 'ceph fsid'
    - Cephモニター: ssh r760xs1 'ceph mon dump'
    - Ceph認証キー: ssh r760xs1 'ceph auth get-key client.kubernetes'

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
DEPLOY_SCRIPT="./deploy-prometheus.sh"

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
log_info "Cephホスト: ${CEPH_USER}@${CEPH_HOST}:${CEPH_PORT}"

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
    
    # 3. Ceph認証キーを取得
    log_info "Ceph認証キーを取得中..."
    CEPH_KEY=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "ceph auth get-key client.kubernetes 2>/dev/null" | tr -d '[:space:]')
    
    if [[ -z "$CEPH_KEY" ]]; then
        log_warn "ceph auth get-keyで認証キーを取得できませんでした"
        log_info "keyringファイルから取得を試みます..."
        
        CEPH_KEY=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "grep -oP 'key\s*=\s*\K.*' /etc/ceph/ceph.client.kubernetes.keyring 2>/dev/null" | tr -d '[:space:]')
        
        if [[ -z "$CEPH_KEY" ]]; then
            log_error "Ceph認証キーを取得できませんでした"
            log_error "リモートホストで以下を確認してください:"
            log_error "  ssh ${CEPH_USER}@${CEPH_HOST} 'ceph auth get-key client.kubernetes'"
            log_error "  ssh ${CEPH_USER}@${CEPH_HOST} 'cat /etc/ceph/ceph.client.kubernetes.keyring'"
            log_error ""
            log_error "client.kubernetesユーザーが存在しない場合は、以下で作成してください:"
            log_error "  ssh ${CEPH_USER}@${CEPH_HOST} 'ceph auth get-or-create client.kubernetes mon \"allow r\" osd \"allow class-read object_prefix rbd_children, allow rwx pool=kubernetes\"'"
            exit 1
        fi
        log_success "keyringファイルから認証キー取得成功"
    else
        log_success "ceph auth get-keyから認証キー取得成功"
    fi
    
    # 認証キーの妥当性チェック（Base64形式か）
    if [[ ! "$CEPH_KEY" =~ ^[A-Za-z0-9+/]+=*$ ]]; then
        log_error "取得した認証キーが不正な形式です: ${CEPH_KEY:0:20}..."
        exit 1
    fi
    
    # 4. Cephプール存在確認
    log_info "Cephプール 'kubernetes' の存在確認中..."
    if ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "ceph osd pool ls 2>/dev/null | grep -q '^kubernetes$'"; then
        log_success "Cephプール 'kubernetes' が存在します"
    else
        log_warn "Cephプール 'kubernetes' が存在しません"
        log_info "プールを作成することを推奨します:"
        log_info "  ssh ${CEPH_USER}@${CEPH_HOST} 'ceph osd pool create kubernetes 128 128'"
        log_info "  ssh ${CEPH_USER}@${CEPH_HOST} 'ceph osd pool application enable kubernetes rbd'"
        log_warn "デプロイは続行しますが、PVC作成時にエラーが発生する可能性があります"
    fi
    
    # Ceph情報サマリー
    log_info ""
    log_info "=========================================="
    log_info "取得したCeph情報"
    log_info "=========================================="
    log_info "取得元ホスト: ${CEPH_USER}@${CEPH_HOST}:${CEPH_PORT}"
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

EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    log_success ""
    log_success "=========================================="
    log_success "全デプロイメント完了!"
    log_success "=========================================="
else
    log_error ""
    log_error "=========================================="
    log_error "デプロイメントに失敗しました"
    log_error "=========================================="
fi

exit $EXIT_CODE
```

## 主な変更点と機能

1. **SSH経由でのCeph情報取得**:
   - `ssh r760xs1 'ceph fsid'` でクラスタID取得
   - `ssh r760xs1 'ceph mon dump'` でモニターアドレス取得
   - `ssh r760xs1 'ceph auth get-key client.kubernetes'` で認証キー取得

2. **SSH接続確認**:
   - デプロイ前にSSH接続をテスト
   - 接続失敗時に詳細なエラーメッセージと対処方法を表示

3. **フォールバック機能**:
   - `ceph mon dump` 失敗時は `/etc/ceph/ceph.conf` から取得
   - `ceph auth get-key` 失敗時は keyring ファイルから取得

4. **追加の検証**:
   - 認証キーのBase64形式チェック
   - Cephプール `kubernetes` の存在確認

## 使用準備

1. **SSH設定** (`~/.ssh/config`):
```
Host r760xs1
    HostName 172.16.200.11
    User root
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null