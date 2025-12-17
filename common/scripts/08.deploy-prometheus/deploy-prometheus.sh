#!/bin/bash

#==============================================================================
# Prometheus Stack Deployment Script for Kubernetes (Fixed Version)
# 対応環境: production, development, sandbox
# 修正内容:
#   - StorageClass作成ロジックの一本化（Helmではなく手動作成に統一）
#   - 作成順序の明確化
#   - エラーハンドリングの強化
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
    --recreate-sc              既存のStorageClassを削除して再作成
    --dry-run                   実行せずに設定のみ表示
    -h, --help                  このヘルプを表示

例:
    $(basename "$0") -e production -c "AQBRxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=="
    $(basename "$0") -e development -c "AQBRxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx==" -m "10.0.0.1:6789,10.0.0.2:6789"

修正内容:
    - StorageClass作成はHelm chartではなく手動作成に統一
    - 作成順序: Secret → CSI Driver → StorageClass → Namespace → Prometheus Stack
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
        echo "StorageClass作成: Helm chartではなく手動作成"
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

#==============================================================================
# Phase 1: Ceph CSI Driver デプロイ
#==============================================================================
if [[ "$SKIP_CEPH" == false ]]; then
    log_info "=========================================="
    log_info "Phase 1: Ceph CSI Driverのデプロイ"
    log_info "=========================================="
    
    # Helm リポジトリ追加
    log_info "Helmリポジトリを追加しています..."
    helm repo add ceph-csi https://ceph.github.io/csi-charts
    helm repo update
    log_success "Helmリポジトリの追加完了"
    
    #--------------------------------------------------------------------------
    # Step 1: Secret作成（Ceph認証情報）
    #--------------------------------------------------------------------------
    log_info "Step 1: Ceph認証情報のSecretを作成しています..."
    
    # Base64エンコード
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
    
    log_success "Secret 'csi-rbd-secret' を作成しました (namespace: kube-system)"
    
    #--------------------------------------------------------------------------
    # Step 2: モニターリスト変換
    #--------------------------------------------------------------------------
    log_info "Step 2: Cephモニターリストを変換しています..."
    
    if [[ -z "$CEPH_MONITORS" ]]; then
        log_error "Cephモニターアドレスが指定されていません"
        exit 1
    fi
    
    # カンマ区切りからYAML配列形式へ変換
    IFS=',' read -ra MONITOR_ARRAY <<< "$CEPH_MONITORS"
    MONITOR_YAML=""
    for monitor in "${MONITOR_ARRAY[@]}"; do
        MONITOR_YAML="${MONITOR_YAML}      - \"${monitor}\"\n"
    done
    
    log_success "モニターリストの変換完了"
    
    #--------------------------------------------------------------------------
    # Step 3: Ceph CSI values.yaml 作成（StorageClass作成は無効）
    #--------------------------------------------------------------------------
    log_info "Step 3: Ceph CSI values.yamlを作成しています..."
    
    cat > "${CONFIG_DIR}/ceph-csi-rbd-values-${ENVIRONMENT}.yaml" << EOF
# Ceph CSI Driver設定
csiConfig:
  - clusterID: "${CEPH_CLUSTER_ID}"
    monitors:
$(echo -e "$MONITOR_YAML")

# StorageClassはHelm chartでは作成しない（手動作成に統一）
storageClass:
  create: false

# 既存のSecretを使用
secret:
  create: false
  name: csi-rbd-secret

# Provisioner設定
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

# Node Plugin設定
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
    
    log_success "values.yamlを作成しました: ${CONFIG_DIR}/ceph-csi-rbd-values-${ENVIRONMENT}.yaml"
    
    #--------------------------------------------------------------------------
    # Step 4: Helm install (CSI Driver本体)
    #--------------------------------------------------------------------------
    log_info "Step 4: Ceph CSI Driverをインストールしています..."
    
    helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
        --namespace kube-system \
        --values "${CONFIG_DIR}/ceph-csi-rbd-values-${ENVIRONMENT}.yaml" \
        --version 3.12.2 \
        --wait \
        --timeout 10m
    
    log_success "Ceph CSI Driverのインストール完了"
    
    #--------------------------------------------------------------------------
    # Step 5: StorageClass作成（手動）
    #--------------------------------------------------------------------------
    log_info "Step 5: StorageClassを作成しています..."
    
    # StorageClass存在チェック
    if kubectl get storageclass "$STORAGE_CLASS_NAME" &> /dev/null; then
        if [[ "$RECREATE_SC" == true ]]; then
            log_warn "StorageClass '${STORAGE_CLASS_NAME}' が既に存在します"
            
            # 使用中のPVCチェック
            log_info "StorageClassを使用しているPVCを確認しています..."
            PVC_LIST=$(kubectl get pvc --all-namespaces -o json | \
                jq -r ".items[] | select(.spec.storageClassName == \"${STORAGE_CLASS_NAME}\") | \"\(.metadata.namespace)/\(.metadata.name)\"")
            
            if [[ -n "$PVC_LIST" ]]; then
                PVC_COUNT=$(echo "$PVC_LIST" | wc -l)
                log_error "StorageClassを使用しているPVCが ${PVC_COUNT} 個存在します:"
                echo "$PVC_LIST"
                log_error "再作成を中止します（PVCを先に削除してください）"
                exit 1
            fi
            
            log_info "StorageClassを削除します..."
            kubectl delete storageclass "$STORAGE_CLASS_NAME"
            log_success "StorageClassを削除しました"
        else
            log_warn "StorageClass '${STORAGE_CLASS_NAME}' が既に存在します"
            log_info "既存のStorageClassを使用します（再作成する場合は --recreate-sc を指定）"
            
            # 既存StorageClassの設定確認
            log_info "既存StorageClassの設定:"
            kubectl get storageclass "$STORAGE_CLASS_NAME" -o yaml | grep -E "provisioner|clusterID|pool"
            
            # 次のステップへ進む
            log_info "StorageClass作成をスキップします"
        fi
    fi
    
    # StorageClassが存在しない、または削除された場合は作成
    if ! kubectl get storageclass "$STORAGE_CLASS_NAME" &> /dev/null; then
        log_info "StorageClass '${STORAGE_CLASS_NAME}' を作成します..."
        
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
  monitors: "172.16.200.11:6789,172.16.200.12:6789,172.16.200.13:6789,172.16.200.14:6789,172.16.200.15:6789"
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
        
        log_success "StorageClass '${STORAGE_CLASS_NAME}' を作成しました"
    fi
    
    # StorageClass作成確認
    log_info "StorageClassの作成を確認しています..."
    if kubectl get storageclass "$STORAGE_CLASS_NAME" &> /dev/null; then
        log_success "StorageClass '${STORAGE_CLASS_NAME}' が正常に存在します"
        kubectl get storageclass "$STORAGE_CLASS_NAME"
    else
        log_error "StorageClass '${STORAGE_CLASS_NAME}' の作成に失敗しました"
        exit 1
    fi
    
    log_success "Phase 1完了: Ceph CSI Driverのデプロイが完了しました"
fi

#==============================================================================
# Phase 2: Prometheus Stack デプロイ
#==============================================================================
log_info ""
log_info "=========================================="
log_info "Phase 2: Prometheus Stackのデプロイ"
log_info "=========================================="

#------------------------------------------------------------------------------
# Step 1: Namespace作成
#------------------------------------------------------------------------------
log_info "Step 1: Namespaceを作成しています..."

kubectl create namespace "$PROMETHEUS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
log_success "Namespace '${PROMETHEUS_NAMESPACE}' を作成しました"

#------------------------------------------------------------------------------
# Step 2: Helm リポジトリ追加
#------------------------------------------------------------------------------
log_info "Step 2: Helmリポジトリを追加しています..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
log_success "Helmリポジトリの追加完了"

#------------------------------------------------------------------------------
# Step 3: Prometheus Stack values.yaml 作成
#------------------------------------------------------------------------------
log_info "Step 3: Prometheus Stack values.yamlを作成しています..."

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

log_success "values.yamlを作成しました: ${CONFIG_DIR}/prometheus-stack-values-${ENVIRONMENT}.yaml"

#------------------------------------------------------------------------------
# Step 4: Helm install (Prometheus Stack)
#------------------------------------------------------------------------------
log_info "Step 4: Prometheus Stackをインストールしています..."
log_info "このステップでPVCが自動作成され、PVが自動プロビジョニングされます"

helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace "$PROMETHEUS_NAMESPACE" \
    --values "${CONFIG_DIR}/prometheus-stack-values-${ENVIRONMENT}.yaml" \
    --version 69.2.0 \
    --wait \
    --timeout 15m

log_success "Prometheus Stackのインストール完了"

log_success "Phase 2完了: Prometheus Stackのデプロイが完了しました"

#==============================================================================
# デプロイ確認
#==============================================================================
echo ""
log_info "=========================================="
log_info "デプロイ状態の確認"
log_info "=========================================="
echo ""

echo "=== StorageClass ==="
kubectl get storageclass "$STORAGE_CLASS_NAME" 2>/dev/null || log_warn "StorageClassが見つかりません"
echo ""

echo "=== Pod状態 (namespace: ${PROMETHEUS_NAMESPACE}) ==="
kubectl get pods -n "$PROMETHEUS_NAMESPACE"
echo ""

echo "=== Service一覧 (namespace: ${PROMETHEUS_NAMESPACE}) ==="
kubectl get svc -n "$PROMETHEUS_NAMESPACE"
echo ""

echo "=== PVC一覧 (namespace: ${PROMETHEUS_NAMESPACE}) ==="
kubectl get pvc -n "$PROMETHEUS_NAMESPACE"
echo ""

echo "=== PV一覧 (Ceph RBD) ==="
kubectl get pv | grep -E "NAME|${STORAGE_CLASS_NAME}" || log_warn "PVが見つかりません"
echo ""

#==============================================================================
# アクセス情報
#==============================================================================
log_info "=========================================="
log_info "アクセス方法"
log_info "=========================================="
echo ""
echo "Prometheus:"
echo "  kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/prometheus-stack-kube-prom-prometheus 9090:9090"
echo "  アクセス: http://localhost:9090"
echo ""
echo "Grafana:"
echo "  kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/prometheus-stack-grafana 3000:80"
echo "  アクセス: http://localhost:3000"
echo "  ユーザー名: admin"
echo "  パスワード: admin (初回ログイン後に変更してください)"
echo ""
echo "Alertmanager:"
echo "  kubectl port-forward -n $PROMETHEUS_NAMESPACE svc/prometheus-stack-kube-prom-alertmanager 9093:9093"
echo "  アクセス: http://localhost:9093"
echo ""

log_success "=========================================="
log_success "全デプロイメント完了!"
log_success "=========================================="