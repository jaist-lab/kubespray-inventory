#!/bin/bash

#==============================================================================
# PV強制削除スクリプト
# rpc error: code = Internal desc = grpc: error while marshaling: 
# string field contains invalid UTF-8 エラーを解決
#==============================================================================

set -e

# カラーコード定義
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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# ヘルプ関数
show_help() {
    cat << EOF
使用方法: $(basename "$0") [OPTIONS]

このスクリプトは、Ceph CSI Driverが削除できないPVを強制削除します。
特に "string field contains invalid UTF-8" エラーが発生している場合に有効です。

OPTIONS:
    -e, --environment <env>     環境指定 (production/development/sandbox)
    -p, --pv-name <name>        削除するPV名（指定しない場合は対象PV一覧を表示）
    --all                       該当するすべてのPVを削除
    --dry-run                   実行せずに対象PVのみ表示
    -h, --help                  このヘルプを表示

処理内容:
    1. PVからfinalizerを削除
    2. PVのclaimRefを削除
    3. PVを強制削除
    4. Ceph RBD Imageを確認（残っている場合は手動削除が必要）

例:
    # 対象PVを確認
    $(basename "$0") -e production --dry-run

    # 特定のPVを削除
    $(basename "$0") -e production -p pvc-xxxx-xxxx-xxxx

    # すべての該当PVを削除
    $(basename "$0") -e production --all

注意:
    - この操作は取り消せません
    - Ceph RBD Imageは手動削除が必要な場合があります
    - 本番環境では慎重に実行してください
EOF
}

# デフォルト値
ENVIRONMENT=""
PV_NAME=""
DELETE_ALL=false
DRY_RUN=false

# 引数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--pv-name)
            PV_NAME="$2"
            shift 2
            ;;
        --all)
            DELETE_ALL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "不明なオプション: $1"
            show_help
            exit 1
            ;;
    esac
done

# 必須パラメータチェック
if [[ -z "$ENVIRONMENT" ]]; then
    log_error "環境 (-e) は必須です"
    show_help
    exit 1
fi

# 環境別設定
case $ENVIRONMENT in
    production)
        KUBECONFIG_PATH="${HOME}/.kube/config-production"
        STORAGE_CLASS_NAME="ceph-rbd-prod"
        ;;
    development)
        KUBECONFIG_PATH="${HOME}/.kube/config-development"
        STORAGE_CLASS_NAME="ceph-rbd-dev"
        ;;
    sandbox)
        KUBECONFIG_PATH="${HOME}/.kube/config-sandbox"
        STORAGE_CLASS_NAME="ceph-rbd-sandbox"
        ;;
    *)
        log_error "不正な環境: $ENVIRONMENT"
        show_help
        exit 1
        ;;
esac

# Kubeconfig設定
export KUBECONFIG="$KUBECONFIG_PATH"

# Kubernetes接続確認
log_info "Kubernetesクラスタへの接続を確認しています..."
if ! kubectl cluster-info &> /dev/null; then
    log_error "Kubernetesクラスタに接続できません"
    log_error "Kubeconfig: $KUBECONFIG_PATH"
    exit 1
fi
log_success "Kubernetesクラスタに接続しました"

#==============================================================================
# 対象PV一覧取得
#==============================================================================
log_info "対象PVを検索しています..."

if [[ -n "$PV_NAME" ]]; then
    # 特定のPVを指定
    if ! kubectl get pv "$PV_NAME" &> /dev/null; then
        log_error "PV '${PV_NAME}' が見つかりません"
        exit 1
    fi
    TARGET_PVS="$PV_NAME"
else
    # StorageClassに一致するPVを取得
    TARGET_PVS=$(kubectl get pv -o json | \
        jq -r ".items[] | select(.spec.storageClassName == \"${STORAGE_CLASS_NAME}\") | .metadata.name" || echo "")
    
    if [[ -z "$TARGET_PVS" ]]; then
        log_info "削除対象のPVが見つかりません（StorageClass: ${STORAGE_CLASS_NAME}）"
        exit 0
    fi
fi

# PV一覧表示
PV_COUNT=$(echo "$TARGET_PVS" | wc -l)
log_info "対象PV数: ${PV_COUNT}"
echo ""
echo "=== 対象PV一覧 ==="

echo "$TARGET_PVS" | while read pv; do
    if [[ -n "$pv" ]]; then
        STATUS=$(kubectl get pv "$pv" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        CAPACITY=$(kubectl get pv "$pv" -o jsonpath='{.spec.capacity.storage}' 2>/dev/null || echo "Unknown")
        CLAIM=$(kubectl get pv "$pv" -o jsonpath='{.spec.claimRef.namespace}/{.spec.claimRef.name}' 2>/dev/null || echo "None")
        VOLUME_HANDLE=$(kubectl get pv "$pv" -o jsonpath='{.spec.csi.volumeHandle}' 2>/dev/null || echo "Unknown")
        
        log_info "PV: $pv"
        log_info "  Status: $STATUS"
        log_info "  Capacity: $CAPACITY"
        log_info "  Claim: $CLAIM"
        log_info "  VolumeHandle: $VOLUME_HANDLE"
        
        # イベント確認（UTF-8エラーがあるか）
        UTF8_ERROR=$(kubectl get events --field-selector involvedObject.name="$pv" 2>/dev/null | \
            grep -i "invalid UTF-8" || echo "")
        
        if [[ -n "$UTF8_ERROR" ]]; then
            log_warn "  UTF-8エラー検出: あり"
        fi
        echo ""
    fi
done

# ドライラン終了
if [[ "$DRY_RUN" == true ]]; then
    log_info "ドライラン完了: 上記のPVが削除対象です"
    exit 0
fi

# 確認プロンプト
if [[ "$DELETE_ALL" == false && -z "$PV_NAME" ]]; then
    log_error "削除するPVを指定してください: -p <pv-name> または --all"
    exit 1
fi

if [[ "$DELETE_ALL" == true ]]; then
    echo ""
    log_warn "=========================================="
    log_warn "警告: ${PV_COUNT}個のPVを削除します"
    log_warn "=========================================="
    log_warn "この操作は取り消せません。続行しますか？"
    echo ""
    read -p "続行するには 'yes' と入力してください: " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "削除をキャンセルしました"
        exit 0
    fi
fi

#==============================================================================
# PV削除処理
#==============================================================================
log_info ""
log_info "=========================================="
log_info "PV削除処理開始"
log_info "=========================================="

SUCCESS_COUNT=0
FAILED_COUNT=0

echo "$TARGET_PVS" | while read pv; do
    if [[ -z "$pv" ]]; then
        continue
    fi
    
    log_info ""
    log_info "PV '${pv}' を削除しています..."
    
    # Step 1: Finalizerを確認
    FINALIZERS=$(kubectl get pv "$pv" -o jsonpath='{.metadata.finalizers}' 2>/dev/null || echo "[]")
    log_info "  現在のfinalizers: $FINALIZERS"
    
    # Step 2: Finalizerを削除
    if [[ "$FINALIZERS" != "[]" && "$FINALIZERS" != "" ]]; then
        log_info "  finalizersを削除しています..."
        if kubectl patch pv "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null; then
            log_success "  finalizersを削除しました"
        else
            log_warn "  finalizersの削除に失敗しました（続行します）"
        fi
    else
        log_info "  finalizersは設定されていません"
    fi
    
    # Step 3: claimRefを削除（Releasedステータスの場合）
    STATUS=$(kubectl get pv "$pv" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$STATUS" == "Released" || "$STATUS" == "Failed" ]]; then
        log_info "  claimRefを削除しています（Status: ${STATUS}）..."
        if kubectl patch pv "$pv" -p '{"spec":{"claimRef":null}}' --type=merge 2>/dev/null; then
            log_success "  claimRefを削除しました"
        else
            log_warn "  claimRefの削除に失敗しました（続行します）"
        fi
    fi
    
    # Step 4: PVを削除
    log_info "  PVを削除しています..."
    
    # 通常の削除を試行
    if kubectl delete pv "$pv" --timeout=30s 2>/dev/null; then
        log_success "  PV '${pv}' を削除しました"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_warn "  通常の削除に失敗しました。強制削除を試行します..."
        
        # 強制削除
        if kubectl delete pv "$pv" --force --grace-period=0 2>/dev/null; then
            log_success "  PV '${pv}' を強制削除しました"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            log_error "  PV '${pv}' の削除に失敗しました"
            FAILED_COUNT=$((FAILED_COUNT + 1))
            
            # エラー詳細を取得
            log_error "  エラー詳細:"
            kubectl get pv "$pv" -o yaml 2>&1 | head -20 | while read line; do
                log_error "    $line"
            done
        fi
    fi
done

#==============================================================================
# 結果サマリー
#==============================================================================
log_info ""
log_info "=========================================="
log_info "削除結果"
log_info "=========================================="
log_info "成功: ${SUCCESS_COUNT}個"
log_info "失敗: ${FAILED_COUNT}個"

# 残存PV確認
REMAINING_PVS=$(kubectl get pv -o json 2>/dev/null | \
    jq -r ".items[] | select(.spec.storageClassName == \"${STORAGE_CLASS_NAME}\") | .metadata.name" || echo "")

if [[ -n "$REMAINING_PVS" ]]; then
    REMAINING_COUNT=$(echo "$REMAINING_PVS" | wc -l)
    log_warn ""
    log_warn "残存PV: ${REMAINING_COUNT}個"
    echo "$REMAINING_PVS" | while read pv; do
        if [[ -n "$pv" ]]; then
            log_warn "  - $pv"
        fi
    done
else
    log_success ""
    log_success "すべてのPVが削除されました"
fi

#==============================================================================
# Ceph RBD Image確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "Ceph RBD Image確認"
log_info "=========================================="
log_info "PV削除後もCeph RBD Imageが残っている可能性があります"
log_info ""
log_info "確認方法:"
log_info "  ssh r760xs1 'rbd ls kubernetes'"
log_info ""
log_info "手動削除方法:"
log_info "  ssh r760xs1 'rbd rm kubernetes/<image-name>'"
log_info ""
log_warn "注意: RBD Imageを削除すると、データが完全に失われます"

if [[ $FAILED_COUNT -gt 0 ]]; then
    log_error ""
    log_error "=========================================="
    log_error "一部のPV削除に失敗しました"
    log_error "=========================================="
    log_error ""
    log_error "追加の対処方法:"
    log_error "1. PVの詳細を確認:"
    log_error "   kubectl get pv <pv-name> -o yaml"
    log_error ""
    log_error "2. 手動でfinalizerを編集:"
    log_error "   kubectl edit pv <pv-name>"
    log_error "   # metadata.finalizers を削除"
    log_error ""
    log_error "3. RBDマッピングを確認:"
    log_error "   kubectl get pods -n kube-system | grep ceph-csi"
    log_error "   kubectl logs -n kube-system <ceph-csi-pod>"
    log_error ""
    log_error "4. Ceph側で確認:"
    log_error "   ssh r760xs1 'rbd ls kubernetes'"
    log_error "   ssh r760xs1 'rbd info kubernetes/<image-name>'"
    exit 1
else
    log_success ""
    log_success "=========================================="
    log_success "PV削除完了"
    log_success "=========================================="
    exit 0
fi