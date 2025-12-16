#!/bin/bash

#==============================================================================
# Prometheus Stack Deployment Script for Kubernetes
# 対応環境: production, development, sandbox
#==============================================================================


# deploy-prometheus.sh
# Prometheus Stack (Prometheus, Grafana, Alertmanager) を Kubernetes にデプロイするスクリプト
# Ceph ストレージとの統合を含む

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
CEPH_KEY=""
CEPH_CLUSTER_ID=""
CEPH_MONITORS=""
CEPH_POOL="kubernetes"
PROMETHEUS_NAMESPACE="monitoring"
SKIP_CEPH=false
DRY_RUN=false
RECREATE_SC=false
CONFIG_DIR="${HOME}/kubernetes/monitoring-configs"

# ヘルプ関数
show_help() {
    cat << EOF
使用方法: $(basename "$0") -e <environment> -c <ceph-key> [オプション]

必須パラメータ:
    -e, --environment <env>     環境指定 (production/development/sandbox)
    -c, --ceph-key <key>        Ceph認証キー（Base64形式）

オプションパラメータ:
    -i, --cluster-id <id>       CephクラスタID (デフォルト: 自動取得)
    -m, --monitors <list>       Cephモニターのリスト (例: "10.0.0.1:6789,10.0.0.2:6789")
    -p, --pool <name>           Cephプール名 (デフォルト: kubernetes)
    -n, --namespace <ns>        Prometheusのネームスペース (デフォルト: monitoring)
    --skip-ceph                 Ceph CSI Driverのデプロイをスキップ
    --recreate-sc              既存のStorageClassを再作成
    --dry-run                   実行せずに設定のみ表示
    -h, --help                  このヘルプを表示

例:
    $(basename "$0") -e production -c "AQBRxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=="
    $(basename "$0") -e development -c "AQBRxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx==" -m "10.0.0.1:6789,10.0.0.2:6789"
EOF
}

# 引数解析
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
            PROMETHEUS_NAMESPACE="$2"
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

if [[ "$SKIP_CEPH" == false ]] && [[ -z "$CEPH_KEY" ]]; then
    log_error "Ceph認証キー (-c) は必須です（--skip-ceph を使用しない場合）"
    show_help
    exit 1
fi

# 環境別設定
case $ENVIRONMENT in
    production)
        KUBECONFIG_PATH="${HOME}/.kube/config-production"
        STORAGE_CLASS_NAME="ceph-rbd-prod"
        PROMETHEUS_RETENTION="30d"
        PROMETHEUS_STORAGE_SIZE="100Gi"
        GRAFANA_STORAGE_SIZE="10Gi"
        ALERTMANAGER_STORAGE_SIZE="10Gi"
        ;;
    development)
        KUBECONFIG_PATH="${HOME}/.kube/config-development"
        STORAGE_CLASS_NAME="ceph-rbd-dev"
        PROMETHEUS_RETENTION="15d"
        PROMETHEUS_STORAGE_SIZE="50Gi"
        GRAFANA_STORAGE_SIZE="5Gi"
        ALERTMANAGER_STORAGE_SIZE="10Gi"
        ;;
    sandbox)
        KUBECONFIG_PATH="${HOME}/.kube/config-sandbox"
        STORAGE_CLASS_NAME="ceph-rbd-sandbox"
        PROMETHEUS_RETENTION="7d"
        PROMETHEUS_STORAGE_SIZE="20Gi"
        GRAFANA_STORAGE_SIZE="5Gi"
        ALERTMANAGER_STORAGE_SIZE="10Gi"
        ;;
    *)
        log_error "不正な環境: $ENVIRONMENT"
        show_help
        exit 1
        ;;
esac

# Kubeconfig設定
export KUBECONFIG="$KUBECONFIG_PATH"

# ドライラン表示
if [[ "$DRY_RUN" == true ]]; then
    echo "=== ドライラン: 以下の設定でデプロイされます ==="
    echo "環境: $ENVIRONMENT"
    echo "Kubeconfig: $KUBECONFIG_PATH"
    echo "Cephプール: $CEPH_POOL"
    echo "StorageClass: $STORAGE_CLASS_NAME"
    echo "Prometheusネームスペース: $PROMETHEUS_NAMESPACE"
    echo "Prometheus保持期間: $PROMETHEUS_RETENTION"
    echo "Prometheusストレージサイズ: $PROMETHEUS_STORAGE_SIZE"
    echo "Grafanaストレージサイズ: $GRAFANA_STORAGE_SIZE"
    if [[ "$SKIP_CEPH" == false ]]; then
        echo "Ceph CSI Driver: デプロイする"
        echo "CephクラスタID: ${CEPH_CLUSTER_ID:-自動取得}"
        echo "Cephモニター: ${CEPH_MONITORS:-自動取得}"
    else
        echo "Ceph CSI Driver: スキップ"
    fi
    echo "=================================="
    exit 0
fi

# Kubernetes接続確認
log_info "Kubernetesクラスタへの接続を確認しています..."
if ! kubectl cluster-info &> /dev/null; then
    log_error "Kubernetesクラスタに接続できません"
    log_error "Kubeconfig: $KUBECONFIG_PATH"
    exit 1
fi
log_success "Kubernetesクラスタに接続しました"

# 設定ファイルディレクトリ作成
mkdir -p "$CONFIG_DIR"

# Ceph CSI Driver デプロイ
if [[ "$SKIP_CEPH" == false ]]; then
    log_info "Ceph CSI Driverをデプロイしています..."
    
    # Helm リポジトリ追加
    helm repo add ceph-csi https://ceph.github.io/csi-charts
    helm repo update
    
    # Secret作成（Ceph認証情報）
    log_info "Ceph認証情報のSecretを作成しています..."
    
    # Base64エンコード確認
    CEPH_USER_BASE64=$(echo -n "kubernetes" | base64)
    
    kubectl apply -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: csi-rbd-secret
  namespace: kube-system
type: Opaque
data:
  userID: ${CEPH_USER_BASE64}
  userKey: ${CEPH_KEY}
EOF
    
    # モニターリスト変換（カンマ区切りからYAML配列形式へ）
    if [[ -n "$CEPH_MONITORS" ]]; then
        IFS=',' read -ra MONITOR_ARRAY <<< "$CEPH_MONITORS"
        MONITOR_YAML=""
        for monitor in "${MONITOR_ARRAY[@]}"; do
            MONITOR_YAML="${MONITOR_YAML}      - \"${monitor}\"\n"
        done
    else
        log_error "Cephモニターアドレスが指定されていません"
        exit 1
    fi
    
    # StorageClass存在チェック
    SC_CREATE=true
    if kubectl get storageclass "$STORAGE_CLASS_NAME" &> /dev/null; then
        log_warn "StorageClass '${STORAGE_CLASS_NAME}' が既に存在します"
        
        if [[ "$RECREATE_SC" == true ]]; then
            log_info "StorageClassを再作成します..."
            
            # 使用中のPVCチェック
            PVC_COUNT=$(kubectl get pvc --all-namespaces -o json | \
                jq -r ".items[] | select(.spec.storageClassName == \"${STORAGE_CLASS_NAME}\") | .metadata.name" | wc -l)
            
            if [[ $PVC_COUNT -gt 0 ]]; then
                log_error "StorageClassを使用しているPVCが ${PVC_COUNT} 個存在します"
                log_error "再作成を中止します"
                exit 1
            fi
            
            kubectl delete storageclass "$STORAGE_CLASS_NAME"
            SC_CREATE=true
        else
            log_info "既存のStorageClassを使用します"
            SC_CREATE=false
        fi
    fi
    
    # Ceph CSI values.yaml 作成
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
    
    # Helm deploy
    helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
        --namespace kube-system \
        --values "${CONFIG_DIR}/ceph-csi-rbd-values-${ENVIRONMENT}.yaml" \
        --version 3.12.2 \
        --wait \
        --timeout 10m
    
    # StorageClass作成（Helm chartで作成されない場合）
    if [[ "$SC_CREATE" == true ]]; then
        log_info "StorageClass '${STORAGE_CLASS_NAME}' を作成しています..."
        
        cat << EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${STORAGE_CLASS_NAME}
provisioner: rbd.csi.ceph.com
parameters:
  clusterID: "${CEPH_CLUSTER_ID}"
  pool: ${CEPH_POOL}
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: csi-rbd-secret
  csi.storage.k8s.io/provisioner-secret-namespace: kube-system
  csi.storage.k8s.io/controller-expand-secret-name: csi-rbd-secret
  csi.storage.k8s.io/controller-expand-secret-namespace: kube-system
  csi.storage.k8s.io/node-stage-secret-name: csi-rbd-secret
  csi.storage.k8s.io/node-stage-secret-namespace: kube-system
  csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: Immediate
mountOptions:
  - discard
EOF
        
        log_info "StorageClass '${STORAGE_CLASS_NAME}' が作成されました"
    fi
    
    log_success "Ceph CSI Driverのデプロイが完了しました"
fi

# Prometheus Stack デプロイ
log_info "Prometheus Stackをデプロイしています..."

# Namespace作成
kubectl create namespace "$PROMETHEUS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Helm リポジトリ追加
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Prometheus Stack values.yaml 作成
cat > "${CONFIG_DIR}/prometheus-stack-values-${ENVIRONMENT}.yaml" << EOF
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
    
    # 全ServiceMonitor/PodMonitorを自動検出
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false

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
              storage: ${ALERTMANAGER_STORAGE_SIZE}
    
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi

# Grafana設定
grafana:
  enabled: true
  
  persistence:
    enabled: true
    storageClassName: ${STORAGE_CLASS_NAME}
    size: ${GRAFANA_STORAGE_SIZE}
    accessModes:
      - ReadWriteOnce
  
  adminPassword: "admin"  # 初期パスワード（要変更）
  
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi
  
  # デフォルトダッシュボード有効化
  defaultDashboardsEnabled: true

# Node Exporter設定
prometheus-node-exporter:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Kube State Metrics設定
kube-state-metrics:
  resources:
    requests:
      cpu: 10m
      memory: 128Mi
    limits:
      cpu: 100m
      memory: 256Mi

# 共通ラベル
commonLabels:
  environment: ${ENVIRONMENT}
EOF

# Helm deploy
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace "$PROMETHEUS_NAMESPACE" \
    --values "${CONFIG_DIR}/prometheus-stack-values-${ENVIRONMENT}.yaml" \
    --version 69.2.0 \
    --wait \
    --timeout 15m

log_success "Prometheus Stackのデプロイが完了しました"

# デプロイ確認
echo ""
log_info "デプロイ状態を確認しています..."
echo ""

echo "=== Pod状態 ==="
kubectl get pods -n "$PROMETHEUS_NAMESPACE"
echo ""

echo "=== Service一覧 ==="
kubectl get svc -n "$PROMETHEUS_NAMESPACE"
echo ""

echo "=== PVC一覧 ==="
kubectl get pvc -n "$PROMETHEUS_NAMESPACE"
echo ""

echo "=== アクセス方法 ==="
echo "Prometheus: kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/prometheus-stack-kube-prom-prometheus 9090:9090"
echo "Grafana: kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/prometheus-stack-grafana 3000:80"
echo "Alertmanager: kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/prometheus-stack-kube-prom-alertmanager 9093:9093"
echo ""
echo "Grafana初期ログイン情報:"
echo "  ユーザー名: admin"
echo "  パスワード: admin (初回ログイン後に変更してください)"
echo ""

log_success "すべての処理が完了しました"