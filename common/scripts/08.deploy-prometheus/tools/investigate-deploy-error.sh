#!/bin/bash

#==============================================================================
# Prometheus Stack デプロイエラー詳細調査
#==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

log_info "=========================================="
log_info "Prometheus Stack デプロイエラー調査"
log_info "=========================================="

# 1. PVC状態確認
log_info ""
log_info "=== 1. PVC状態確認 ==="
kubectl get pvc -n monitoring

log_info ""
log_info "=== 2. PVC詳細 ==="
for pvc in $(kubectl get pvc -n monitoring -o jsonpath='{.items[*].metadata.name}'); do
    log_info "--- PVC: $pvc ---"
    kubectl describe pvc -n monitoring "$pvc" | grep -A 5 "Status:\|Events:"
done

# 3. PV状態確認
log_info ""
log_info "=== 3. PV状態確認 ==="
kubectl get pv | grep monitoring || echo "No PVs for monitoring namespace"

# 4. Pod状態確認
log_info ""
log_info "=== 4. Pod状態確認 ==="
kubectl get pods -n monitoring

# 5. CSI Driver Provisioner ログ
log_info ""
log_info "=== 5. CSI Provisioner ログ（最新50行） ==="
CSI_POD=$(kubectl get pods -n kube-system -l app=ceph-csi-rbd,app.kubernetes.io/component=provisioner -o jsonpath='{.items[0].metadata.name}')
if [[ -n "$CSI_POD" ]]; then
    log_info "Pod: $CSI_POD"
    kubectl logs -n kube-system "$CSI_POD" -c csi-provisioner --tail=50 | grep -i "error\|fail\|utf" || echo "No errors found"
else
    log_warn "CSI Provisioner Pod not found"
fi

# 6. CSI Driver RBD Plugin ログ
log_info ""
log_info "=== 6. CSI RBD Plugin ログ（最新30行） ==="
if [[ -n "$CSI_POD" ]]; then
    kubectl logs -n kube-system "$CSI_POD" -c csi-rbdplugin --tail=30 | grep -i "error\|fail\|utf" || echo "No errors found"
fi

# 7. イベント確認
log_info ""
log_info "=== 7. 最近のイベント（monitoring namespace） ==="
kubectl get events -n monitoring --sort-by='.lastTimestamp' | tail -20

# 8. StorageClass確認
log_info ""
log_info "=== 8. StorageClass確認 ==="
kubectl get storageclass ceph-rbd-prod -o jsonpath='{.parameters}' | jq .

# 9. Secret確認
log_info ""
log_info "=== 9. Secret確認 ==="
if kubectl get secret -n kube-system csi-rbd-secret &>/dev/null; then
    log_success "Secret 'csi-rbd-secret' exists"
    kubectl get secret -n kube-system csi-rbd-secret -o jsonpath='{.data.userKey}' | base64 -d | wc -c
    echo " bytes (decoded)"
else
    log_error "Secret 'csi-rbd-secret' not found"
fi

# 10. ConfigMap確認
log_info ""
log_info "=== 10. CSI ConfigMap確認 ==="
if kubectl get configmap -n kube-system ceph-csi-config &>/dev/null; then
    kubectl get configmap -n kube-system ceph-csi-config -o jsonpath='{.data.config\.json}' | jq .
else
    log_warn "ConfigMap 'ceph-csi-config' not found"
fi

# 11. Ceph接続テスト
log_info ""
log_info "=== 11. Ceph接続テスト ==="
log_info "CSI NodePlugin Podからのテスト:"
NODE_POD=$(kubectl get pods -n kube-system -l app=ceph-csi-rbd,app.kubernetes.io/component=nodeplugin -o jsonpath='{.items[0].metadata.name}')
if [[ -n "$NODE_POD" ]]; then
    log_info "Pod: $NODE_POD"
    kubectl exec -n kube-system "$NODE_POD" -c csi-rbdplugin -- rbd ls kubernetes 2>&1 | head -10 || log_warn "Cannot list RBD images"
else
    log_warn "CSI NodePlugin Pod not found"
fi

log_info ""
log_info "=========================================="
log_info "調査完了"
log_info "=========================================="