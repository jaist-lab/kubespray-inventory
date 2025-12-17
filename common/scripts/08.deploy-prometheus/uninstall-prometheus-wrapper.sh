#!/bin/bash

#==============================================================================
# Prometheus Stack Uninstall Wrapper Script
# より簡単にアンインストールを実行するためのラッパー
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
    --prometheus-only       Prometheus Stackのみ削除（CSI Driver/StorageClassは残す）
    --complete              完全削除（CSI Driver、StorageClass含む）
    --with-data             Ceph RBD Imageも削除（データ完全削除）
    --force                 確認なしで実行
    --dry-run               削除対象のみ表示
    -h, --help              このヘルプを表示

削除モード:
    1. Prometheus Stackのみ削除（デフォルト）
       - Prometheus Stack (Helm)
       - PVC/Pod
       - Namespace
       ※ StorageClassとCSI Driverは残る

    2. 完全削除 (--complete)
       - 上記 + StorageClass + CSI Driver
       ※ Ceph RBD Imageは残る

    3. データ込み完全削除 (--with-data)
       - 上記 + Ceph RBD Image
       ※ データが完全に失われます

例:
    # Prometheus Stackのみ削除
    $0 -e production

    # 完全削除（CSI Driver、StorageClass含む）
    $0 -e production --complete

    # データ込み完全削除
    $0 -e production --with-data

    # ドライラン（削除対象のみ確認）
    $0 -e production --complete --dry-run

    # 確認なしで実行
    $0 -e production --force

推奨される使用方法:
    1. まず --dry-run で確認
    2. 問題なければ実行
    3. 本番環境では --prometheus-only から始める
EOF
    exit 1
}

# デフォルト値
ENVIRONMENT=""
PROMETHEUS_ONLY=true
COMPLETE=false
WITH_DATA=false
FORCE=false
DRY_RUN=false
UNINSTALL_SCRIPT="./uninstall-prometheus.sh"

# 引数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --prometheus-only)
            PROMETHEUS_ONLY=true
            COMPLETE=false
            WITH_DATA=false
            shift
            ;;
        --complete)
            PROMETHEUS_ONLY=false
            COMPLETE=true
            WITH_DATA=false
            shift
            ;;
        --with-data)
            PROMETHEUS_ONLY=false
            COMPLETE=true
            WITH_DATA=true
            shift
            ;;
        --force)
            FORCE=true
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

# アンインストールスクリプト存在確認
if [[ ! -f "$UNINSTALL_SCRIPT" ]]; then
    log_error "アンインストールスクリプトが見つかりません: $UNINSTALL_SCRIPT"
    log_error "uninstall-prometheus.sh が同じディレクトリに存在することを確認してください"
    exit 1
fi

log_info "=========================================="
log_info "Prometheus Stack アンインストール"
log_info "=========================================="
log_info "環境: $ENVIRONMENT"

# 削除モードの表示
if [[ "$WITH_DATA" == true ]]; then
    log_warn "削除モード: データ込み完全削除"
    log_warn "  - Prometheus Stack"
    log_warn "  - Namespace"
    log_warn "  - PVC/PV"
    log_warn "  - StorageClass"
    log_warn "  - Ceph CSI Driver"
    log_warn "  - Ceph RBD Image（データ完全削除）"
elif [[ "$COMPLETE" == true ]]; then
    log_info "削除モード: 完全削除"
    log_info "  - Prometheus Stack"
    log_info "  - Namespace"
    log_info "  - PVC/PV"
    log_info "  - StorageClass"
    log_info "  - Ceph CSI Driver"
else
    log_info "削除モード: Prometheus Stackのみ削除"
    log_info "  - Prometheus Stack"
    log_info "  - Namespace"
    log_info "  - PVC/PV"
fi

log_info "=========================================="

# アンインストールスクリプト実行
UNINSTALL_ARGS=("-e" "$ENVIRONMENT")

if [[ "$PROMETHEUS_ONLY" == true ]]; then
    UNINSTALL_ARGS+=("--skip-csi")
    UNINSTALL_ARGS+=("--skip-sc")
fi

if [[ "$WITH_DATA" == true ]]; then
    UNINSTALL_ARGS+=("--delete-ceph-images")
fi

if [[ "$FORCE" == true ]]; then
    UNINSTALL_ARGS+=("--force")
fi

if [[ "$DRY_RUN" == true ]]; then
    UNINSTALL_ARGS+=("--dry-run")
fi

log_info "実行コマンド: $UNINSTALL_SCRIPT ${UNINSTALL_ARGS[*]}"
log_info ""

# スクリプト実行
bash "$UNINSTALL_SCRIPT" "${UNINSTALL_ARGS[@]}"

EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    log_success ""
    log_success "=========================================="
    log_success "アンインストール完了!"
    log_success "=========================================="
    
    if [[ "$DRY_RUN" == false ]]; then
        log_info ""
        log_info "次のステップ:"
        
        if [[ "$PROMETHEUS_ONLY" == true ]]; then
            log_info "  - StorageClassとCSI Driverは残っています"
            log_info "  - 完全に削除する場合: $0 -e $ENVIRONMENT --complete"
        elif [[ "$COMPLETE" == true && "$WITH_DATA" == false ]]; then
            log_info "  - Ceph RBD Imageは残っています"
            log_info "  - データも削除する場合: $0 -e $ENVIRONMENT --with-data"
        fi
        
        log_info ""
        log_info "再デプロイする場合:"
        log_info "  ./deploy-prometheus-wrapper-fixed.sh -e $ENVIRONMENT"
    fi
else
    log_error ""
    log_error "=========================================="
    log_error "アンインストールに失敗しました"
    log_error "=========================================="
fi

exit $EXIT_CODE