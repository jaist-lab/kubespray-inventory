#!/bin/bash

#==============================================================================
# Prometheus Stack Uninstall Script for Kubernetes
# 対応環境: production, development, sandbox
#==============================================================================

set -e

# カラーコード定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# デフォルト値
ENVIRONMENT=""
PROMETHEUS_NAMESPACE="monitoring"
SKIP_CSI=false
SKIP_SC=false
FORCE=false
DRY_RUN=false
DELETE_CEPH_IMAGES=false
CEPH_HOST="r760xs1"
CEPH_USER="root"
CEPH_PORT="22"
CEPH_POOL="kubernetes"

# ヘルプ関数
show_help() {
    cat << EOF
使用方法: $(basename "$0") -e <environment> [オプション]

必須パラメータ:
    -e, --environment <env>     環境指定 (production/development/sandbox)

オプションパラメータ:
    -n, --namespace <ns>        Prometheusのネームスペース (デフォルト: monitoring)
    --skip-csi                  Ceph CSI Driverの削除をスキップ
    --skip-sc                   StorageClassの削除をスキップ
    --delete-ceph-images        Ceph RBD Imageも削除（データ完全削除）
    -H, --ceph-host <host>      Cephホスト (デフォルト: r760xs1)
    -u, --ceph-user <user>      Ceph SSHユーザー (デフォルト: root)
    -p, --ceph-port <port>      Ceph SSHポート (デフォルト: 22)
    --pool <name>               Cephプール名 (デフォルト: kubernetes)
    --force                     確認なしで実行
    --dry-run                   実行せずに削除対象のみ表示
    -h, --help                  このヘルプを表示

削除される内容:
    1. Prometheus Stack (Helm release)
    2. PersistentVolumeClaims (PVC)
    3. PersistentVolumes (PV) - reclaimPolicy: Retain の場合は手動削除
    4. Namespace (monitoring)
    5. StorageClass (--skip-sc がない場合)
    6. Ceph CSI Driver (--skip-csi がない場合)
    7. Ceph RBD Images (--delete-ceph-images が指定された場合)

例:
    # Prometheus Stackのみ削除（CSI DriverとStorageClassは残す）
    $(basename "$0") -e production --skip-csi --skip-sc

    # 完全削除（CSI Driver、StorageClass含む）
    $(basename "$0") -e production

    # Ceph RBD Imageも含めて完全削除
    $(basename "$0") -e production --delete-ceph-images

    # ドライラン（削除対象のみ確認）
    $(basename "$0") -e production --dry-run

注意:
    - PVのreclaimPolicyがRetainの場合、PVは手動削除が必要です
    - --delete-ceph-images を使用すると、データが完全に削除されます
    - 本番環境では --dry-run で確認してから実行することを推奨します
EOF
}

# 引数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -n|--namespace)
            PROMETHEUS_NAMESPACE="$2"
            shift 2
            ;;
        --skip-csi)
            SKIP_CSI=true
            shift
            ;;
        --skip-sc)
            SKIP_SC=true
            shift
            ;;
        --delete-ceph-images)
            DELETE_CEPH_IMAGES=true
            shift
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
        --pool)
            CEPH_POOL="$2"
            shift 2
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
# 削除対象の確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "削除対象の確認"
log_info "=========================================="
log_info "環境: $ENVIRONMENT"
log_info "Kubeconfig: $KUBECONFIG_PATH"
log_info ""

# Prometheus Stack確認
if helm list -n "$PROMETHEUS_NAMESPACE" | grep -q "prometheus-stack"; then
    log_info "✓ Prometheus Stack (Helm release)"
    HELM_EXISTS=true
else
    log_warn "  Prometheus Stack (Helm release) は存在しません"
    HELM_EXISTS=false
fi

# Namespace確認
if kubectl get namespace "$PROMETHEUS_NAMESPACE" &> /dev/null; then
    log_info "✓ Namespace: $PROMETHEUS_NAMESPACE"
    NAMESPACE_EXISTS=true
    
    # PVC一覧
    PVC_LIST=$(kubectl get pvc -n "$PROMETHEUS_NAMESPACE" -o json 2>/dev/null | jq -r '.items[].metadata.name' || echo "")
    if [[ -n "$PVC_LIST" ]]; then
        log_info "✓ PVC一覧:"
        echo "$PVC_LIST" | while read pvc; do
            log_info "    - $pvc"
        done
    fi
    
    # Pod一覧
    POD_COUNT=$(kubectl get pods -n "$PROMETHEUS_NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [[ $POD_COUNT -gt 0 ]]; then
        log_info "✓ Pod数: $POD_COUNT"
    fi
else
    log_warn "  Namespace '$PROMETHEUS_NAMESPACE' は存在しません"
    NAMESPACE_EXISTS=false
fi

# StorageClass確認
if [[ "$SKIP_SC" == false ]]; then
    if kubectl get storageclass "$STORAGE_CLASS_NAME" &> /dev/null; then
        log_info "✓ StorageClass: $STORAGE_CLASS_NAME"
        SC_EXISTS=true
        
        # StorageClassを使用しているPVC確認（全Namespace）
        SC_PVC_LIST=$(kubectl get pvc --all-namespaces -o json 2>/dev/null | \
            jq -r ".items[] | select(.spec.storageClassName == \"${STORAGE_CLASS_NAME}\") | \"\(.metadata.namespace)/\(.metadata.name)\"" || echo "")
        if [[ -n "$SC_PVC_LIST" ]]; then
            SC_PVC_COUNT=$(echo "$SC_PVC_LIST" | wc -l)
            log_warn "  StorageClassを使用しているPVCが ${SC_PVC_COUNT} 個存在します:"
            echo "$SC_PVC_LIST" | while read pvc; do
                log_warn "    - $pvc"
            done
        fi
    else
        log_warn "  StorageClass '$STORAGE_CLASS_NAME' は存在しません"
        SC_EXISTS=false
    fi
fi

# CSI Driver確認
if [[ "$SKIP_CSI" == false ]]; then
    if helm list -n kube-system | grep -q "ceph-csi-rbd"; then
        log_info "✓ Ceph CSI Driver (Helm release)"
        CSI_EXISTS=true
    else
        log_warn "  Ceph CSI Driver (Helm release) は存在しません"
        CSI_EXISTS=false
    fi
    
    if kubectl get secret -n kube-system csi-rbd-secret &> /dev/null; then
        log_info "✓ Secret: csi-rbd-secret (kube-system)"
        SECRET_EXISTS=true
    else
        log_warn "  Secret 'csi-rbd-secret' は存在しません"
        SECRET_EXISTS=false
    fi
fi

# PV確認（Retainポリシー）
PV_LIST=$(kubectl get pv -o json 2>/dev/null | \
    jq -r ".items[] | select(.spec.storageClassName == \"${STORAGE_CLASS_NAME}\") | .metadata.name" || echo "")
if [[ -n "$PV_LIST" ]]; then
    PV_COUNT=$(echo "$PV_LIST" | wc -l)
    log_warn "  PVが ${PV_COUNT} 個存在します（reclaimPolicy: Retain の場合は手動削除が必要）:"
    echo "$PV_LIST" | while read pv; do
        log_warn "    - $pv"
    done
fi

# Ceph RBD Image確認
if [[ "$DELETE_CEPH_IMAGES" == true ]]; then
    log_info ""
    log_info "Ceph RBD Image確認（SSH経由）..."
    
    if ssh -p "$CEPH_PORT" -o ConnectTimeout=10 -o BatchMode=yes "${CEPH_USER}@${CEPH_HOST}" "exit" 2>/dev/null; then
        RBD_IMAGES=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "rbd ls ${CEPH_POOL} 2>/dev/null" || echo "")
        if [[ -n "$RBD_IMAGES" ]]; then
            RBD_COUNT=$(echo "$RBD_IMAGES" | wc -l)
            log_warn "  Ceph RBD Imageが ${RBD_COUNT} 個存在します:"
            echo "$RBD_IMAGES" | while read img; do
                log_warn "    - ${CEPH_POOL}/${img}"
            done
        else
            log_info "  Ceph RBD Imageは存在しません"
        fi
    else
        log_error "SSH接続に失敗しました: ${CEPH_USER}@${CEPH_HOST}:${CEPH_PORT}"
        log_error "Ceph RBD Imageの削除をスキップします"
        DELETE_CEPH_IMAGES=false
    fi
fi

log_info ""
log_info "=========================================="

# ドライラン終了
if [[ "$DRY_RUN" == true ]]; then
    log_info "ドライラン完了: 上記のリソースが削除されます"
    exit 0
fi

# 確認プロンプト
if [[ "$FORCE" == false ]]; then
    echo ""
    log_warn "=========================================="
    log_warn "警告: 以下の操作を実行します"
    log_warn "=========================================="
    log_warn "環境: $ENVIRONMENT"
    log_warn "削除内容:"
    [[ "$HELM_EXISTS" == true ]] && log_warn "  - Prometheus Stack (Helm release)"
    [[ "$NAMESPACE_EXISTS" == true ]] && log_warn "  - Namespace: $PROMETHEUS_NAMESPACE (全PVC/Pod含む)"
    [[ "$SC_EXISTS" == true && "$SKIP_SC" == false ]] && log_warn "  - StorageClass: $STORAGE_CLASS_NAME"
    [[ "$CSI_EXISTS" == true && "$SKIP_CSI" == false ]] && log_warn "  - Ceph CSI Driver"
    [[ "$SECRET_EXISTS" == true && "$SKIP_CSI" == false ]] && log_warn "  - Secret: csi-rbd-secret"
    [[ -n "$PV_LIST" ]] && log_warn "  - PV: ${PV_COUNT}個（手動削除が必要な場合あり）"
    [[ "$DELETE_CEPH_IMAGES" == true && -n "$RBD_IMAGES" ]] && log_warn "  - Ceph RBD Image: ${RBD_COUNT}個（データ完全削除）"
    log_warn ""
    log_warn "この操作は取り消せません。続行しますか？"
    log_warn "=========================================="
    echo ""
    read -p "続行するには 'yes' と入力してください: " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        log_info "アンインストールをキャンセルしました"
        exit 0
    fi
fi

#==============================================================================
# Phase 1: Prometheus Stack削除
#==============================================================================
if [[ "$HELM_EXISTS" == true || "$NAMESPACE_EXISTS" == true ]]; then
    log_info ""
    log_info "=========================================="
    log_info "Phase 1: Prometheus Stackの削除"
    log_info "=========================================="
    
    # Helm uninstall
    if [[ "$HELM_EXISTS" == true ]]; then
        log_info "Prometheus Stack (Helm release) を削除しています..."
        helm uninstall prometheus-stack -n "$PROMETHEUS_NAMESPACE" --wait --timeout 10m
        log_success "Prometheus Stackを削除しました"
    fi
    
    # PVC削除（Helm uninstallで削除されない場合）
    if kubectl get namespace "$PROMETHEUS_NAMESPACE" &> /dev/null; then
        PVC_LIST=$(kubectl get pvc -n "$PROMETHEUS_NAMESPACE" -o json 2>/dev/null | jq -r '.items[].metadata.name' || echo "")
        if [[ -n "$PVC_LIST" ]]; then
            log_info "PVCを削除しています..."
            kubectl delete pvc --all -n "$PROMETHEUS_NAMESPACE" --wait --timeout=5m
            log_success "PVCを削除しました"
        fi
    fi
    
    # Namespace削除
    if [[ "$NAMESPACE_EXISTS" == true ]]; then
        log_info "Namespace '${PROMETHEUS_NAMESPACE}' を削除しています..."
        kubectl delete namespace "$PROMETHEUS_NAMESPACE" --wait --timeout=10m
        log_success "Namespaceを削除しました"
    fi
    
    log_success "Phase 1完了: Prometheus Stackを削除しました"
fi

#==============================================================================
# Phase 2: PV削除（reclaimPolicy: Retainの場合）
#==============================================================================
if [[ -n "$PV_LIST" ]]; then
    log_info ""
    log_info "=========================================="
    log_info "Phase 2: PVの削除"
    log_info "=========================================="
    
    echo "$PV_LIST" | while read pv; do
        if [[ -n "$pv" ]]; then
            RECLAIM_POLICY=$(kubectl get pv "$pv" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null || echo "")
            PV_STATUS=$(kubectl get pv "$pv" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            
            log_info "PV '${pv}' の削除を試行中（reclaimPolicy: ${RECLAIM_POLICY}, status: ${PV_STATUS}）..."
            
            if [[ "$RECLAIM_POLICY" == "Retain" && "$PV_STATUS" == "Released" ]]; then
                # Retainポリシーで、Releasedステータスの場合は手動削除
                kubectl delete pv "$pv" --wait --timeout=2m 2>/dev/null && \
                    log_success "PV '${pv}' を削除しました" || \
                    log_warn "PV '${pv}' の削除に失敗しました（手動削除が必要な場合があります）"
            elif [[ "$PV_STATUS" == "Bound" ]]; then
                log_warn "PV '${pv}' はまだBoundステータスです（PVCが残っている可能性）"
            else
                kubectl delete pv "$pv" --wait --timeout=2m 2>/dev/null && \
                    log_success "PV '${pv}' を削除しました" || \
                    log_warn "PV '${pv}' の削除に失敗しました"
            fi
        fi
    done
    
    log_success "Phase 2完了: PV削除を試行しました"
fi

#==============================================================================
# Phase 3: StorageClass削除
#==============================================================================
if [[ "$SKIP_SC" == false && "$SC_EXISTS" == true ]]; then
    log_info ""
    log_info "=========================================="
    log_info "Phase 3: StorageClassの削除"
    log_info "=========================================="
    
    # StorageClassを使用しているPVC再確認
    SC_PVC_LIST=$(kubectl get pvc --all-namespaces -o json 2>/dev/null | \
        jq -r ".items[] | select(.spec.storageClassName == \"${STORAGE_CLASS_NAME}\") | \"\(.metadata.namespace)/\(.metadata.name)\"" || echo "")
    
    if [[ -n "$SC_PVC_LIST" ]]; then
        SC_PVC_COUNT=$(echo "$SC_PVC_LIST" | wc -l)
        log_error "StorageClassを使用しているPVCが ${SC_PVC_COUNT} 個存在します:"
        echo "$SC_PVC_LIST" | while read pvc; do
            log_error "  - $pvc"
        done
        log_error "StorageClassの削除をスキップします"
    else
        log_info "StorageClass '${STORAGE_CLASS_NAME}' を削除しています..."
        kubectl delete storageclass "$STORAGE_CLASS_NAME" --wait --timeout=2m
        log_success "StorageClassを削除しました"
    fi
    
    log_success "Phase 3完了: StorageClass削除を試行しました"
fi

#==============================================================================
# Phase 4: Ceph CSI Driver削除
#==============================================================================
if [[ "$SKIP_CSI" == false ]]; then
    log_info ""
    log_info "=========================================="
    log_info "Phase 4: Ceph CSI Driverの削除"
    log_info "=========================================="
    
    # Helm uninstall
    if [[ "$CSI_EXISTS" == true ]]; then
        log_info "Ceph CSI Driver (Helm release) を削除しています..."
        helm uninstall ceph-csi-rbd -n kube-system --wait --timeout 10m
        log_success "Ceph CSI Driverを削除しました"
    fi
    
    # Secret削除
    if [[ "$SECRET_EXISTS" == true ]]; then
        log_info "Secret 'csi-rbd-secret' を削除しています..."
        kubectl delete secret csi-rbd-secret -n kube-system --wait --timeout=2m
        log_success "Secretを削除しました"
    fi
    
    log_success "Phase 4完了: Ceph CSI Driverを削除しました"
fi

#==============================================================================
# Phase 5: Ceph RBD Image削除（オプション）
#==============================================================================
if [[ "$DELETE_CEPH_IMAGES" == true && -n "$RBD_IMAGES" ]]; then
    log_info ""
    log_info "=========================================="
    log_info "Phase 5: Ceph RBD Imageの削除"
    log_info "=========================================="
    log_warn "警告: Ceph RBD Imageを削除すると、データが完全に失われます"
    
    echo "$RBD_IMAGES" | while read img; do
        if [[ -n "$img" ]]; then
            log_info "RBD Image '${CEPH_POOL}/${img}' を削除しています..."
            if ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "rbd rm ${CEPH_POOL}/${img} 2>/dev/null"; then
                log_success "RBD Image '${img}' を削除しました"
            else
                log_error "RBD Image '${img}' の削除に失敗しました"
            fi
        fi
    done
    
    log_success "Phase 5完了: Ceph RBD Image削除を試行しました"
fi

#==============================================================================
# 最終確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "アンインストール完了後の状態確認"
log_info "=========================================="

# Namespace確認
if kubectl get namespace "$PROMETHEUS_NAMESPACE" &> /dev/null; then
    log_warn "Namespace '${PROMETHEUS_NAMESPACE}' がまだ存在します"
else
    log_success "Namespace '${PROMETHEUS_NAMESPACE}' は削除されました"
fi

# StorageClass確認
if [[ "$SKIP_SC" == false ]]; then
    if kubectl get storageclass "$STORAGE_CLASS_NAME" &> /dev/null; then
        log_warn "StorageClass '${STORAGE_CLASS_NAME}' がまだ存在します"
    else
        log_success "StorageClass '${STORAGE_CLASS_NAME}' は削除されました"
    fi
fi

# PV確認
REMAINING_PV=$(kubectl get pv -o json 2>/dev/null | \
    jq -r ".items[] | select(.spec.storageClassName == \"${STORAGE_CLASS_NAME}\") | .metadata.name" || echo "")
if [[ -n "$REMAINING_PV" ]]; then
    REMAINING_PV_COUNT=$(echo "$REMAINING_PV" | wc -l)
    log_warn "PVが ${REMAINING_PV_COUNT} 個残っています:"
    echo "$REMAINING_PV" | while read pv; do
        STATUS=$(kubectl get pv "$pv" -o jsonpath='{.status.phase}' 2>/dev/null)
        log_warn "  - $pv (status: $STATUS)"
    done
    log_info ""
    log_info "手動削除が必要な場合:"
    echo "$REMAINING_PV" | while read pv; do
        log_info "  kubectl delete pv $pv"
    done
else
    log_success "全てのPVが削除されました"
fi

# CSI Driver確認
if [[ "$SKIP_CSI" == false ]]; then
    if helm list -n kube-system | grep -q "ceph-csi-rbd"; then
        log_warn "Ceph CSI Driver (Helm release) がまだ存在します"
    else
        log_success "Ceph CSI Driver (Helm release) は削除されました"
    fi
fi

log_info ""
log_success "=========================================="
log_success "アンインストール処理が完了しました"
log_success "=========================================="
log_info ""
log_info "環境: $ENVIRONMENT"
log_info "削除されたコンポーネント:"
[[ "$HELM_EXISTS" == true ]] && log_info "  ✓ Prometheus Stack"
[[ "$NAMESPACE_EXISTS" == true ]] && log_info "  ✓ Namespace: $PROMETHEUS_NAMESPACE"
[[ "$SC_EXISTS" == true && "$SKIP_SC" == false ]] && log_info "  ✓ StorageClass: $STORAGE_CLASS_NAME"
[[ "$CSI_EXISTS" == true && "$SKIP_CSI" == false ]] && log_info "  ✓ Ceph CSI Driver"
[[ "$DELETE_CEPH_IMAGES" == true ]] && log_info "  ✓ Ceph RBD Images"

if [[ -n "$REMAINING_PV" ]]; then
    log_info ""
    log_warn "残存リソース:"
    log_warn "  - PV: ${REMAINING_PV_COUNT}個（手動削除が必要）"
fi