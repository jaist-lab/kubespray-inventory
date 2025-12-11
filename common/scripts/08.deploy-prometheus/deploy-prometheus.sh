#!/bin/bash

#==============================================================================
# Prometheus Stack Deployment Script for Kubernetes
# 対応環境: production, development, sandbox
#==============================================================================

set -e

# 色定義
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
    echo -e "${RED}[ERROR]${NC} $1"
}

# 使用方法表示
usage() {
    cat << EOF
使用方法: $0 [OPTIONS]

OPTIONS:
    -e, --environment ENV    環境を指定 (production|development|sandbox) [必須]
    -c, --ceph-key KEY      Ceph認証キー [必須]
    -i, --cluster-id ID     CephクラスタID (デフォルト: 6ba61fd6-e71f-4a4c-8dc8-9ad3af1bd1f4)
    -m, --monitors MONITORS Cephモニターリスト (カンマ区切り)
    -p, --pool POOL         Cephプール名 (デフォルト: kubernetes)
    -n, --namespace NS      Prometheusネームスペース (デフォルト: monitoring)
    --skip-ceph             Ceph CSI Driverのデプロイをスキップ
    --recreate-sc           既存のStorageClassを削除して再作成
    --dry-run               実際のデプロイを行わず、設定のみ表示
    -h, --help              このヘルプを表示

例:
    $0 -e production -c "AQDxxxxxxxxxxxxx=="
    $0 -e development -c "AQDxxxxxxxxxxxxx==" -i "custom-cluster-id"
    $0 --environment sandbox --ceph-key "AQDxxxxxxxxxxxxx==" --dry-run

EOF
    exit 1
}

# デフォルト値
CEPH_CLUSTER_ID="6ba61fd6-e71f-4a4c-8dc8-9ad3af1bd1f4"
CEPH_MONITORS="172.16.200.11:6789,172.16.200.12:6789,172.16.200.13:6789,172.16.200.14:6789,172.16.200.15:6789"
CEPH_POOL="kubernetes"
CEPH_USER="kubernetes"
NAMESPACE="monitoring"
SKIP_CEPH=false
RECREATE_SC=false
DRY_RUN=false
CONFIG_DIR="${HOME}/kubernetes/monitoring-configs"

# 引数解析
ENVIRONMENT=""
CEPH_KEY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -c|--ceph-key)
            CEPH_KEY="$2"
            shift 2
            ;;
        -i|--cluster-id)
            CEPH_CLUSTER_ID="$2"
            shift 2
            ;;
        -m|--monitors)
            CEPH_MONITORS="$2"
            shift 2
            ;;
        -p|--pool)
            CEPH_POOL="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
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
    log_error "無効な環境: $ENVIRONMENT (production, development, sandbox のいずれかを指定してください)"
    exit 1
fi

if [[ -z "$CEPH_KEY" ]] && [[ "$SKIP_CEPH" == false ]]; then
    log_error "Ceph認証キーが指定されていません (--skip-ceph を使用する場合は不要)"
    usage
fi

# 環境別設定
case $ENVIRONMENT in
    production)
        KUBECONFIG_PATH="${HOME}/.kube/config-production"
        STORAGE_CLASS_NAME="ceph-rbd-prod"
        PROMETHEUS_RETENTION="30d"
        PROMETHEUS_STORAGE_SIZE="100Gi"
        GRAFANA_STORAGE_SIZE="10Gi"
        ;;
    development)
        KUBECONFIG_PATH="${HOME}/.kube/config-development"
        STORAGE_CLASS_NAME="ceph-rbd-dev"
        PROMETHEUS_RETENTION="15d"
        PROMETHEUS_STORAGE_SIZE="50Gi"
        GRAFANA_STORAGE_SIZE="5Gi"
        ;;
    sandbox)
        KUBECONFIG_PATH="${HOME}/.kube/config-sandbox"
        STORAGE_CLASS_NAME="ceph-rbd-sandbox"
        PROMETHEUS_RETENTION="7d"
        PROMETHEUS_STORAGE_SIZE="20Gi"
        GRAFANA_STORAGE_SIZE="5Gi"
        ;;
esac

# KUBECONFIG設定
export KUBECONFIG="$KUBECONFIG_PATH"

# 設定表示
log_info "=========================================="
log_info "Prometheus Stack デプロイ設定"
log_info "=========================================="
log_info "環境: $ENVIRONMENT"
log_info "KUBECONFIG: $KUBECONFIG_PATH"
log_info "ネームスペース: $NAMESPACE"
log_info "CephクラスタID: $CEPH_CLUSTER_ID"
log_info "Cephプール: $CEPH_POOL"
log_info "StorageClass: $STORAGE_CLASS_NAME"
log_info "Prometheus保持期間: $PROMETHEUS_RETENTION"
log_info "Prometheusストレージ: $PROMETHEUS_STORAGE_SIZE"
log_info "Grafanaストレージ: $GRAFANA_STORAGE_SIZE"
log_info "Ceph CSIスキップ: $SKIP_CEPH"
log_info "StorageClass再作成: $RECREATE_SC"
log_info "ドライラン: $DRY_RUN"
log_info "=========================================="

if [[ "$DRY_RUN" == true ]]; then
    log_warn "ドライランモード: 実際のデプロイは行いません"
    exit 0
fi

# kubectl接続確認
log_info "Kubernetesクラスタへの接続確認中..."
if ! kubectl cluster-info &> /dev/null; then
    log_error "Kubernetesクラスタに接続できません。KUBECONFIGを確認してください: $KUBECONFIG_PATH"
    exit 1
fi
log_success "クラスタ接続OK"

# 設定ディレクトリ作成
mkdir -p "$CONFIG_DIR"

#==============================================================================
# Ceph CSI Driver デプロイ
#==============================================================================
if [[ "$SKIP_CEPH" == false ]]; then
    log_info "Ceph CSI Driverをデプロイします..."
    
    # 既存StorageClassのチェック
    log_info "既存のStorageClass '${STORAGE_CLASS_NAME}' を確認中..."
    if kubectl get storageclass "$STORAGE_CLASS_NAME" &> /dev/null; then
        log_warn "StorageClass '${STORAGE_CLASS_NAME}' が既に存在します"
        
        if [[ "$RECREATE_SC" == true ]]; then
            # PVC使用状況確認
            PVC_COUNT=$(kubectl get pvc --all-namespaces -o json | jq -r ".items[] | select(.spec.storageClassName == \"${STORAGE_CLASS_NAME}\") | .metadata.name" | wc -l)
            
            if [[ $PVC_COUNT -gt 0 ]]; then
                log_error "StorageClass '${STORAGE_CLASS_NAME}' を使用しているPVCが ${PVC_COUNT} 個存在します"
                log_error "使用中のPVC:"
                kubectl get pvc --all-namespaces -o json | jq -r ".items[] | select(.spec.storageClassName == \"${STORAGE_CLASS_NAME}\") | \"\(.metadata.namespace)/\(.metadata.name)\""
                log_error ""
                log_error "StorageClassを削除するには、まずPVCを削除してください"
                exit 1
            fi
            
            log_warn "StorageClassを削除して再作成します..."
            kubectl delete storageclass "$STORAGE_CLASS_NAME"
            log_success "StorageClass削除完了"
        else
            log_info "既存のStorageClassを使用します（再作成する場合は --recreate-sc オプションを使用）"
            log_info "Ceph CSI Driverの設定のみ更新します..."
        fi
    fi
    
    # Secretの作成
    log_info "Ceph認証情報Secretを作成中..."
    kubectl create secret generic csi-rbd-secret \
        --from-literal=userID="$CEPH_USER" \
        --from-literal=userKey="$CEPH_KEY" \
        --namespace=kube-system \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Secret作成完了"
    
    # Helmリポジトリ追加
    log_info "Helmリポジトリを追加中..."
    helm repo add ceph-csi https://ceph.github.io/csi-charts 2>/dev/null || true
    helm repo update
    log_success "Helmリポジトリ更新完了"
    
    # モニターリストを配列に変換
    IFS=',' read -ra MONITOR_ARRAY <<< "$CEPH_MONITORS"
    MONITOR_YAML=""
    for monitor in "${MONITOR_ARRAY[@]}"; do
        MONITOR_YAML="${MONITOR_YAML}      - \"${monitor}\"\n"
    done
    
    # StorageClass作成設定
    SC_CREATE="true"
    if kubectl get storageclass "$STORAGE_CLASS_NAME" &> /dev/null && [[ "$RECREATE_SC" == false ]]; then
        SC_CREATE="false"
    fi
    
    # Ceph CSI values.yaml作成
    log_info "Ceph CSI設定ファイルを生成中..."
    cat > "${CONFIG_DIR}/ceph-csi-rbd-values-${ENVIRONMENT}.yaml" << EOF
csiConfig:
  - clusterID: "${CEPH_CLUSTER_ID}"
    monitors:
$(echo -e "$MONITOR_YAML")

storageClass:
  create: ${SC_CREATE}
  name: ${STORAGE_CLASS_NAME}
  clusterID: "${CEPH_CLUSTER_ID}"
  pool: ${CEPH_POOL}
  reclaimPolicy: Retain
  allowVolumeExpansion: true
  mountOptions:
    - discard

secret:
  create: false
  name: csi-rbd-secret

provisioner:
  name: provisioner
  replicaCount: 2
  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m

nodeplugin:
  name: nodeplugin
  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 500m
EOF
    
    log_success "設定ファイル生成完了: ${CONFIG_DIR}/ceph-csi-rbd-values-${ENVIRONMENT}.yaml"
    log_info "StorageClass作成設定: ${SC_CREATE}"
    
    # Ceph CSI Driverデプロイ
    log_info "Ceph CSI Driverをデプロイ中..."
    helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
        --namespace kube-system \
        --values "${CONFIG_DIR}/ceph-csi-rbd-values-${ENVIRONMENT}.yaml" \
        --version 3.12.2 \
        --wait \
        --timeout 10m
    
    log_success "Ceph CSI Driverデプロイ完了"
    
    # 確認
    log_info "デプロイ状況確認中..."
    kubectl get pods -n kube-system -l app=ceph-csi-rbd
    kubectl get storageclass "$STORAGE_CLASS_NAME"
    
    log_success "Ceph CSI Driver デプロイ完了"
else
    log_warn "Ceph CSI Driverのデプロイをスキップしました"
fi

#==============================================================================
# Prometheus Stack デプロイ
#==============================================================================
log_info "Prometheus Stackをデプロイします..."

# ネームスペース作成
log_info "ネームスペース作成中: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Helmリポジトリ追加
log_info "Prometheus Helmリポジトリを追加中..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update
log_success "Helmリポジトリ更新完了"

# Prometheus values.yaml作成
log_info "Prometheus設定ファイルを生成中..."
cat > "${CONFIG_DIR}/prometheus-stack-values-${ENVIRONMENT}.yaml" << EOF
# Prometheus Stack設定 - ${ENVIRONMENT}環境

# Prometheus設定
prometheus:
  prometheusSpec:
    retention: ${PROMETHEUS_RETENTION}
    retentionSize: "$(echo $PROMETHEUS_STORAGE_SIZE | sed 's/Gi/GB/')"
    
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: ${STORAGE_CLASS_NAME}
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: ${PROMETHEUS_STORAGE_SIZE}
    
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 8Gi
    
    # サービスモニター自動検出
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    
  # Ingress設定（必要に応じて有効化）
  ingress:
    enabled: false

# Alertmanager設定
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: ${STORAGE_CLASS_NAME}
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi
  
  ingress:
    enabled: false

# Grafana設定
grafana:
  enabled: true
  
  persistence:
    enabled: true
    storageClassName: ${STORAGE_CLASS_NAME}
    size: ${GRAFANA_STORAGE_SIZE}
    accessModes:
      - ReadWriteOnce
  
  adminPassword: "admin"  # 初期パスワード（デプロイ後に変更推奨）
  
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi
  
  ingress:
    enabled: false
  
  # デフォルトダッシュボード
  defaultDashboardsEnabled: true
  
  # 追加データソース
  additionalDataSources: []

# Node Exporter
prometheus-node-exporter:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Kube State Metrics
kube-state-metrics:
  resources:
    requests:
      cpu: 10m
      memory: 128Mi
    limits:
      cpu: 100m
      memory: 256Mi

# 環境別タグ
commonLabels:
  environment: ${ENVIRONMENT}
EOF

log_success "設定ファイル生成完了: ${CONFIG_DIR}/prometheus-stack-values-${ENVIRONMENT}.yaml"

# Prometheus Stackデプロイ
log_info "Prometheus Stackをデプロイ中..."
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace "$NAMESPACE" \
    --values "${CONFIG_DIR}/prometheus-stack-values-${ENVIRONMENT}.yaml" \
    --wait \
    --timeout 15m

log_success "Prometheus Stackデプロイ完了"

#==============================================================================
# デプロイ確認
#==============================================================================
log_info "=========================================="
log_info "デプロイ確認"
log_info "=========================================="

log_info "Pod一覧:"
kubectl get pods -n "$NAMESPACE"

log_info ""
log_info "Service一覧:"
kubectl get svc -n "$NAMESPACE"

log_info ""
log_info "PVC一覧:"
kubectl get pvc -n "$NAMESPACE"

log_info ""
log_info "=========================================="
log_success "デプロイ完了!"
log_info "=========================================="
log_info ""
log_info "アクセス方法:"
log_info ""
log_info "1. Prometheus:"
log_info "   kubectl port-forward -n $NAMESPACE svc/prometheus-stack-kube-prom-prometheus 9090:9090"
log_info "   ブラウザで http://localhost:9090 にアクセス"
log_info ""
log_info "2. Grafana:"
log_info "   kubectl port-forward -n $NAMESPACE svc/prometheus-stack-grafana 3000:80"
log_info "   ブラウザで http://localhost:3000 にアクセス"
log_info "   初期ユーザー名: admin"
log_info "   初期パスワード: admin"
log_info ""
log_info "3. Alertmanager:"
log_info "   kubectl port-forward -n $NAMESPACE svc/prometheus-stack-kube-prom-alertmanager 9093:9093"
log_info "   ブラウザで http://localhost:9093 にアクセス"
log_info ""
log_info "設定ファイル保存先: ${CONFIG_DIR}"
log_info "=========================================="