#!/bin/bash

#==============================================================================
# Ceph CSI Driver - UTF-8エラー診断スクリプト
# Invalid UTF-8エラーの根本原因を特定
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
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# デフォルト値
CEPH_HOST="r760xs1"
CEPH_USER="root"
CEPH_PORT="22"
CEPH_POOL="kubernetes"
ENVIRONMENT="production"

# 引数解析
while [[ $# -gt 0 ]]; do
    case $1 in
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
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --pool)
            CEPH_POOL="$2"
            shift 2
            ;;
        *)
            echo "不明なオプション: $1"
            exit 1
            ;;
    esac
done

# 環境別設定
case $ENVIRONMENT in
    production)
        STORAGE_CLASS_NAME="ceph-rbd-prod"
        ;;
    development)
        STORAGE_CLASS_NAME="ceph-rbd-dev"
        ;;
    sandbox)
        STORAGE_CLASS_NAME="ceph-rbd-sandbox"
        ;;
esac

log_info "=========================================="
log_info "Ceph CSI Driver - UTF-8エラー診断"
log_info "=========================================="
log_info "Cephホスト: ${CEPH_USER}@${CEPH_HOST}:${CEPH_PORT}"
log_info "環境: $ENVIRONMENT"
log_info ""

#==============================================================================
# 1. SSH接続確認
#==============================================================================
log_info "=========================================="
log_info "1. SSH接続確認"
log_info "=========================================="

if ssh -p "$CEPH_PORT" -o ConnectTimeout=10 -o BatchMode=yes "${CEPH_USER}@${CEPH_HOST}" "exit" 2>/dev/null; then
    log_success "SSH接続成功"
else
    log_error "SSH接続失敗"
    log_error "ホスト: ${CEPH_USER}@${CEPH_HOST}:${CEPH_PORT}"
    exit 1
fi

#==============================================================================
# 2. CephクラスタID確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "2. CephクラスタID確認"
log_info "=========================================="

# 生のデータ取得
CLUSTER_ID_RAW=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "ceph fsid" 2>/dev/null)
log_info "生の出力: '$CLUSTER_ID_RAW'"
log_info "生の長さ: ${#CLUSTER_ID_RAW} バイト"

# 16進数表示
echo "16進数表示:"
echo "$CLUSTER_ID_RAW" | xxd | head -3

# クリーンアップ
CLUSTER_ID_CLEAN=$(echo "$CLUSTER_ID_RAW" | tr -d '[:cntrl:]' | tr -d '[:space:]' | tr -cd '[:print:]')
log_info "クリーン後: '$CLUSTER_ID_CLEAN'"
log_info "クリーン後長さ: ${#CLUSTER_ID_CLEAN} バイト"

# UUID形式チェック
if [[ "$CLUSTER_ID_CLEAN" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    log_success "UUID形式: 正常"
else
    log_error "UUID形式: 異常"
    log_error "期待形式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    log_error "実際: $CLUSTER_ID_CLEAN"
fi

# LC_ALL=C での取得比較
CLUSTER_ID_LC=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" "LC_ALL=C ceph fsid" 2>/dev/null | tr -d '[:space:]')
if [[ "$CLUSTER_ID_CLEAN" != "$CLUSTER_ID_LC" ]]; then
    log_warn "LC_ALL=C での取得結果が異なります"
    log_warn "通常: $CLUSTER_ID_CLEAN"
    log_warn "LC_ALL=C: $CLUSTER_ID_LC"
fi

#==============================================================================
# 3. Cephモニターアドレス確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "3. Cephモニターアドレス確認"
log_info "=========================================="

MON_RAW=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" \
    "ceph mon dump 2>/dev/null" | grep -oP '\d+\.\d+\.\d+\.\d+:\d+' | paste -sd ',' -)
log_info "モニターアドレス: '$MON_RAW'"
log_info "長さ: ${#MON_RAW} バイト"

# 各アドレスをチェック
IFS=',' read -ra ADDRS <<< "$MON_RAW"
for addr in "${ADDRS[@]}"; do
    addr_trimmed=$(echo "$addr" | xargs)
    log_info "チェック中: '$addr_trimmed'"
    
    if [[ "$addr_trimmed" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+$ ]]; then
        log_success "  形式: 正常"
    else
        log_error "  形式: 異常"
        echo "$addr" | xxd
    fi
done

#==============================================================================
# 4. Ceph認証キー確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "4. Ceph認証キー確認"
log_info "=========================================="

AUTH_RAW=$(ssh -p "$CEPH_PORT" "${CEPH_USER}@${CEPH_HOST}" \
    "ceph auth get-or-create client.kubernetes mon 'allow r' osd 'allow rwx pool=${CEPH_POOL}' 2>/dev/null")
log_info "認証情報の長さ: ${#AUTH_RAW} バイト"

# キー抽出
KEY=$(echo "$AUTH_RAW" | grep -oP 'key\s*=\s*\K[A-Za-z0-9+/=]+' | head -n1 | tr -d '[:space:]')
log_info "抽出したキー: '${KEY:0:20}...'"
log_info "キーの長さ: ${#KEY} バイト"

# Base64形式チェック
if [[ "$KEY" =~ ^[A-Za-z0-9+/]+=*$ ]]; then
    log_success "Base64形式: 正常"
else
    log_error "Base64形式: 異常"
    echo "キーの16進数表示:"
    echo "$KEY" | xxd | head -3
fi

# Base64デコードテスト
if echo "$KEY" | base64 -d &>/dev/null; then
    DECODED_LEN=$(echo "$KEY" | base64 -d | wc -c)
    log_success "Base64デコード: 成功（デコード後: ${DECODED_LEN}バイト）"
else
    log_error "Base64デコード: 失敗"
fi

#==============================================================================
# 5. Kubernetes Secret確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "5. Kubernetes Secret確認"
log_info "=========================================="

if kubectl get secret -n kube-system csi-rbd-secret &>/dev/null; then
    log_info "Secret: 存在"
    
    # userKeyを確認
    USER_KEY_B64=$(kubectl get secret -n kube-system csi-rbd-secret -o jsonpath='{.data.userKey}')
    log_info "userKey (Base64): ${#USER_KEY_B64} バイト"
    
    # デコード
    USER_KEY=$(echo "$USER_KEY_B64" | base64 -d 2>/dev/null || echo "")
    log_info "userKey (デコード後): ${#USER_KEY} バイト"
    
    # 比較
    if [[ "$USER_KEY" == "$KEY" ]]; then
        log_success "CephキーとSecretキー: 一致"
    else
        log_error "CephキーとSecretキー: 不一致"
        log_error "  Ceph   : '${KEY:0:20}...'"
        log_error "  Secret : '${USER_KEY:0:20}...'"
        
        echo "差分（16進数）:"
        echo "Ceph:"
        echo "$KEY" | xxd | head -3
        echo "Secret:"
        echo "$USER_KEY" | xxd | head -3
    fi
else
    log_warn "Secret: 存在しません"
fi

#==============================================================================
# 6. StorageClass確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "6. StorageClass確認"
log_info "=========================================="

if kubectl get storageclass "$STORAGE_CLASS_NAME" &>/dev/null; then
    log_info "StorageClass: $STORAGE_CLASS_NAME"
    
    # clusterIDを取得
    SC_CLUSTER_ID=$(kubectl get storageclass "$STORAGE_CLASS_NAME" -o jsonpath='{.parameters.clusterID}')
    log_info "  clusterID: '$SC_CLUSTER_ID'"
    log_info "  長さ: ${#SC_CLUSTER_ID} バイト"
    
    # 比較
    if [[ "$SC_CLUSTER_ID" == "$CLUSTER_ID_CLEAN" ]]; then
        log_success "  CephクラスタIDと一致"
    else
        log_error "  CephクラスタIDと不一致"
        log_error "  Ceph : '$CLUSTER_ID_CLEAN'"
        log_error "  SC   : '$SC_CLUSTER_ID'"
    fi
    
    # モニターアドレスを取得
    SC_MONITORS=$(kubectl get storageclass "$STORAGE_CLASS_NAME" -o jsonpath='{.parameters.monitors}')
    log_info "  monitors: '$SC_MONITORS'"
else
    log_warn "StorageClass '$STORAGE_CLASS_NAME' は存在しません"
fi

#==============================================================================
# 7. CSI Driver確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "7. CSI Driver確認"
log_info "=========================================="

# CSI Driver Podを取得
CSI_PODS=$(kubectl get pods -n kube-system -l app=ceph-csi-rbd -o jsonpath='{.items[*].metadata.name}')

if [[ -n "$CSI_PODS" ]]; then
    log_info "CSI Driver Pods: $(echo $CSI_PODS | wc -w)個"
    
    for pod in $CSI_PODS; do
        log_info "  Pod: $pod"
        
        # Podのステータス
        STATUS=$(kubectl get pod -n kube-system "$pod" -o jsonpath='{.status.phase}')
        log_info "    Status: $STATUS"
        
        # エラーログを確認
        ERROR_COUNT=$(kubectl logs -n kube-system "$pod" -c csi-provisioner --tail=100 2>/dev/null | \
            grep -i "utf-8\|marshal\|error" | wc -l)
        
        if [[ $ERROR_COUNT -gt 0 ]]; then
            log_warn "    エラーログ: ${ERROR_COUNT}件"
            echo "    最近のエラー:"
            kubectl logs -n kube-system "$pod" -c csi-provisioner --tail=100 2>/dev/null | \
                grep -i "utf-8\|marshal" | tail -5 | sed 's/^/      /'
        else
            log_success "    エラーログ: なし"
        fi
    done
else
    log_warn "CSI Driver Podが見つかりません"
fi

#==============================================================================
# 8. csi-configmap確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "8. CSI ConfigMap確認"
log_info "=========================================="

if kubectl get configmap -n kube-system ceph-csi-config &>/dev/null; then
    log_info "ConfigMap: 存在"
    
    # ConfigMapの内容を取得
    CONFIG_DATA=$(kubectl get configmap -n kube-system ceph-csi-config -o jsonpath='{.data.config\.json}')
    log_info "ConfigMap内容:"
    echo "$CONFIG_DATA" | jq '.' 2>/dev/null || echo "$CONFIG_DATA" | sed 's/^/  /'
    
    # clusterIDをチェック
    CM_CLUSTER_ID=$(echo "$CONFIG_DATA" | jq -r '.[0].clusterID' 2>/dev/null || echo "")
    if [[ -n "$CM_CLUSTER_ID" ]]; then
        log_info "  ConfigMap clusterID: '$CM_CLUSTER_ID'"
        if [[ "$CM_CLUSTER_ID" == "$CLUSTER_ID_CLEAN" ]]; then
            log_success "  CephクラスタIDと一致"
        else
            log_error "  CephクラスタIDと不一致"
        fi
    fi
else
    log_warn "ConfigMap 'ceph-csi-config' は存在しません"
fi

#==============================================================================
# 9. 最近のイベント確認
#==============================================================================
log_info ""
log_info "=========================================="
log_info "9. 最近のKubernetesイベント確認"
log_info "=========================================="

UTF8_EVENTS=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | \
    grep -i "utf-8\|marshal" | tail -10)

if [[ -n "$UTF8_EVENTS" ]]; then
    log_warn "UTF-8関連イベント: 発見"
    echo "$UTF8_EVENTS"
else
    log_success "UTF-8関連イベント: なし"
fi

#==============================================================================
# 10. 診断結果サマリー
#==============================================================================
log_info ""
log_info "=========================================="
log_info "診断結果サマリー"
log_info "=========================================="

# 問題のフラグ
ISSUES=0

# クラスタIDチェック
if [[ ! "$CLUSTER_ID_CLEAN" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    log_error "✗ クラスタIDの形式が不正です"
    ISSUES=$((ISSUES + 1))
fi

# 認証キーチェック
if [[ ! "$KEY" =~ ^[A-Za-z0-9+/]+=*$ ]] || ! echo "$KEY" | base64 -d &>/dev/null; then
    log_error "✗ 認証キーが不正です"
    ISSUES=$((ISSUES + 1))
fi

# Secretチェック
if kubectl get secret -n kube-system csi-rbd-secret &>/dev/null; then
    if [[ "$USER_KEY" != "$KEY" ]]; then
        log_error "✗ SecretとCephの認証キーが一致しません"
        ISSUES=$((ISSUES + 1))
    fi
fi

# StorageClassチェック
if kubectl get storageclass "$STORAGE_CLASS_NAME" &>/dev/null; then
    if [[ "$SC_CLUSTER_ID" != "$CLUSTER_ID_CLEAN" ]]; then
        log_error "✗ StorageClassのクラスタIDが一致しません"
        ISSUES=$((ISSUES + 1))
    fi
fi

log_info ""
if [[ $ISSUES -eq 0 ]]; then
    log_success "=========================================="
    log_success "診断完了: 問題は検出されませんでした"
    log_success "=========================================="
else
    log_error "=========================================="
    log_error "診断完了: ${ISSUES}個の問題が検出されました"
    log_error "=========================================="
    log_error ""
    log_error "推奨される対処:"
    log_error "1. 既存のSecret/StorageClass/CSI Driverを削除"
    log_error "2. 修正版デプロイスクリプトで再インストール"
    log_error "3. deploy-prometheus-v2.sh を使用してください"
fi

exit $ISSUES