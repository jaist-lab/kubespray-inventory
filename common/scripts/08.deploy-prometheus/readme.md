# Kubernetes環境（Production/Development/Sandbox）向けのPrometheus Stackデプロイメント自動化スクリプト

## 配置先

```
/home/jaist-lab/kubernetes/kubespray/inventory/common/scripts/08.deploy-prometheus/
├── deploy-prometheus.sh          # メインスクリプト
├── README.md                      # このファイル
└── configs/                       # 自動生成される設定ファイル
    ├── ceph-csi-rbd-values-production.yaml
    ├── ceph-csi-rbd-values-development.yaml
    ├── ceph-csi-rbd-values-sandbox.yaml
    ├── prometheus-stack-values-production.yaml
    ├── prometheus-stack-values-development.yaml
    └── prometheus-stack-values-sandbox.yaml
```

## 機能

- **対話モード**: 引数なしで実行すると対話的に環境と設定を選択可能
- **非対話モード**: コマンドライン引数で全設定を指定して自動実行
- **環境別設定**: Production/Development/Sandboxで異なるリソース設定を自動適用
- **Ceph CSI統合**: Cephストレージバックエンドの自動セットアップ
- **ドライラン**: 実際のデプロイ前に設定確認が可能

## 環境別デフォルト設定

### Production
- ストレージクラス: `ceph-rbd-prod`
- Prometheus保持期間: 30日
- Prometheusストレージ: 100Gi
- Grafanaストレージ: 10Gi
- KUBECONFIG: `~/.kube/config-production`

### Development
- ストレージクラス: `ceph-rbd-dev`
- Prometheus保持期間: 15日
- Prometheusストレージ: 50Gi
- Grafanaストレージ: 5Gi
- KUBECONFIG: `~/.kube/config-development`

### Sandbox
- ストレージクラス: `ceph-rbd-sandbox`
- Prometheus保持期間: 7日
- Prometheusストレージ: 20Gi
- Grafanaストレージ: 5Gi
- KUBECONFIG: `~/.kube/config-sandbox`

## 使用方法

### 1. 対話モード（推奨）

引数なしで実行すると対話的に設定を選択できます：

```bash
cd /home/jaist-lab/kubernetes/kubespray/inventory/common/scripts/08.deploy-prometheus
chmod +x deploy-prometheus.sh
./deploy-prometheus.sh
```

対話例：
```
==========================================
Prometheus Stack デプロイメントウィザード
==========================================

デプロイする環境を選択してください:
  1) Production
  2) Development
  3) Sandbox

選択 (1/2/3): 1

Ceph CSI Driverをデプロイしますか?
  1) はい（推奨）
  2) いいえ（既にデプロイ済みの場合）

選択 (1/2): 1

Ceph認証キーを入力してください: AQDxxxxxxxxxxxxx==

CephクラスタIDを変更しますか?
  現在の値: 6ba61fd6-e71f-4a4c-8dc8-9ad3af1bd1f4

変更する場合は新しい値を入力（Enterでデフォルト値を使用）:

...
```

### 2. 非対話モード

全パラメータをコマンドライン引数で指定：

#### Production環境へのデプロイ
```bash
./deploy-prometheus.sh \\
  -e production \\
  -c \"AQDxxxxxxxxxxxxx==\"
```

#### Development環境へのカスタムデプロイ
```bash
./deploy-prometheus.sh \\
  -e development \\
  -c \"AQDxxxxxxxxxxxxx==\" \\
  -i \"custom-cluster-id\" \\
  -p \"my-pool\" \\
  -n \"custom-monitoring\"
```

#### Sandbox環境へのCeph CSIスキップデプロイ
```bash
./deploy-prometheus.sh \\
  -e sandbox \\
  --skip-ceph
```

#### ドライラン（設定確認のみ）
```bash
./deploy-prometheus.sh \\
  -e production \\
  -c \"AQDxxxxxxxxxxxxx==\" \\
  --dry-run
```

## コマンドラインオプション

| オプション | 短縮形 | 説明 | デフォルト値 |
|-----------|--------|------|-------------|
| `--environment` | `-e` | 環境指定 (production/development/sandbox) | - |
| `--ceph-key` | `-c` | Ceph認証キー | - |
| `--cluster-id` | `-i` | CephクラスタID | 6ba61fd6-e71f-4a4c-8dc8-9ad3af1bd1f4 |
| `--monitors` | `-m` | Cephモニターリスト（カンマ区切り） | 172.16.200.11:6789,... |
| `--pool` | `-p` | Cephプール名 | kubernetes |
| `--namespace` | `-n` | Prometheusネームスペース | monitoring |
| `--skip-ceph` | - | Ceph CSI Driverのデプロイをスキップ | false |
| `--dry-run` | - | 設定確認のみ（デプロイしない） | false |
| `--non-interactive` | - | 対話モード無効化 | false |
| `--help` | `-h` | ヘルプ表示 | - |

## デプロイされるコンポーネント

### Ceph CSI Driver（オプション）
- **Provisioner**: 2レプリカ
- **Node Plugin**: 各ノードに1つ
- **Storage Class**: 環境別のRBDストレージクラス

### Prometheus Stack
- **Prometheus**: メトリクス収集・保存
- **Grafana**: 可視化ダッシュボード
- **Alertmanager**: アラート管理
- **Node Exporter**: ノードメトリクス収集
- **Kube State Metrics**: Kubernetesリソースメトリクス

## デプロイ後のアクセス方法

### 1. Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
```

ブラウザで http://localhost:9090 にアクセス

### 2. Grafana

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
```

ブラウザで http://localhost:3000 にアクセス
- 初期ユーザー名: `admin`
- 初期パスワード: `admin`

**重要**: 初回ログイン後、必ずパスワードを変更してください。

### 3. Alertmanager

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093
```

ブラウザで http://localhost:9093 にアクセス

## 状態確認コマンド

### Pod状態確認
```bash
kubectl get pods -n monitoring
kubectl get pods -n kube-system -l app=ceph-csi-rbd
```

### Service確認
```bash
kubectl get svc -n monitoring
```

### PVC確認
```bash
kubectl get pvc -n monitoring
```

### StorageClass確認
```bash
kubectl get storageclass
```

## トラブルシューティング

### Podが起動しない場合

```bash
# Pod詳細確認
kubectl describe pod <pod-name> -n monitoring

# ログ確認
kubectl logs <pod-name> -n monitoring
```

### PVCがPendingのまま

```bash
# PVC詳細確認
kubectl describe pvc <pvc-name> -n monitoring

# StorageClass確認
kubectl get storageclass

# Ceph CSI Driverのログ確認
kubectl logs -n kube-system -l app=ceph-csi-rbd
```

### Ceph接続エラー

```bash
# Cephクラスタ状態確認
ceph -s

# Ceph認証確認
ceph auth get client.kubernetes

# Secret確認
kubectl get secret csi-rbd-secret -n kube-system -o yaml
```

## アップグレード

既存のデプロイをアップグレードする場合：

```bash
# 同じコマンドを再実行（helm upgrade --install が使用される）
./deploy-prometheus.sh -e production -c \"AQDxxxxxxxxxxxxx==\"
```

## アンインストール

### Prometheus Stack削除
```bash
helm uninstall prometheus-stack -n monitoring
kubectl delete namespace monitoring
```

### Ceph CSI Driver削除
```bash
helm uninstall ceph-csi-rbd -n kube-system
kubectl delete secret csi-rbd-secret -n kube-system
kubectl delete storageclass ceph-rbd-prod  # または ceph-rbd-dev, ceph-rbd-sandbox
```

## カスタマイズ

### 設定ファイルの編集

自動生成された設定ファイルを編集して、より詳細なカスタマイズが可能：

```bash
# 設定ファイル編集
vi configs/prometheus-stack-values-production.yaml

# 編集した設定で再デプロイ
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \\
  --namespace monitoring \\
  --values configs/prometheus-stack-values-production.yaml
```

### リソース調整

環境に応じてリソース要求・制限を調整する場合は、スクリプト内の該当部分を編集：

```bash
# スクリプト編集
vi deploy-prometheus.sh

# 該当箇所（例: Production設定）
production)
    PROMETHEUS_STORAGE_SIZE=\"100Gi\"  # 変更可能
    GRAFANA_STORAGE_SIZE=\"10Gi\"      # 変更可能
    ...
```

## 注意事項

1. **Ceph認証キー**: 実際の認証キーは安全に管理し、スクリプトや設定ファイルに平文で残さないこと
2. **初期パスワード**: Grafanaの初期パスワード（admin/admin）は必ず変更すること
3. **KUBECONFIG**: 各環境の正しいKUBECONFIGファイルパスを確認すること
4. **ストレージ容量**: Cephクラスタに十分な空き容量があることを確認すること
5. **ネットワーク**: Cephモニターへのネットワーク接続が可能であることを確認すること

## 参考情報

- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Ceph CSI Driver](https://github.com/ceph/ceph-csi)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
