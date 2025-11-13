# ArgoCD デプロイメントスクリプト集

Kubernetes環境にArgoCDをデプロイするためのスクリプト集です。
環境変数（KUBECONFIG）による動的な環境切り替えに対応しています。

## 前提条件

- Kubernetesクラスターが構築済み
- kubectlコマンドが利用可能
- 適切なkubeconfigファイルが存在

## 環境設定

### 1. 環境切り替え機能のセットアップ
```bash
./0.setup_env.sh
source ~/.bashrc
```

### 2. Kubernetes環境の切り替え
```bash
# 利用可能な環境を確認
k8s_env

# sandbox環境に切り替え
k8s_env sandbox

# production環境に切り替え
k8s_env production
```

## ArgoCD インストール手順

### 1. 環境確認
```bash
./1.check_environment.sh
```

### 2. ArgoCDデプロイ
```bash
./2.deploy_argocd.sh
```

### 3. NodePort設定
```bash
./3.set_nodeport.sh
```

### 4. パスワード設定
```bash
./4.set_password.sh
```

デフォルトパスワード: `jaileon02`

### 5. 動作確認
```bash
./5.check_after_install.sh
# または
argocd-check
```

## ArgoCD CLIインストール
```bash
./6.install_argocd_cli_simple.sh
```

## アンインストール
```bash
./99.uninstall-argocd.sh
```

## スクリプト一覧

| スクリプト | 説明 |
|-----------|------|
| 0.setup_env.sh | 環境切り替え機能のセットアップ |
| 1.check_environment.sh | Kubernetes環境の確認 |
| 2.deploy_argocd.sh | ArgoCDのデプロイ |
| 3.set_nodeport.sh | NodePortの設定 |
| 4.set_password.sh | 管理者パスワードの設定 |
| 5.check_after_install.sh | インストール後の動作確認 |
| 88.install_sample_application.sh | サンプルアプリケーションのインストール |
| 89.uninstall_sample_application.sh | サンプルアプリケーションのインストール |
| 99.uninstall_argocd.sh | ArgoCDのアンインストール |

## 環境変数

- `KUBECONFIG`: Kubernetesクラスター設定ファイルのパス
- `K8S_CLUSTER`: 現在の環境名（sandbox, productionなど）
- `KUBESPRAY_DIR`: Kubesprayのルートディレクトリ

## 使用例
```bash
# 環境確認
k8s_env

# sandbox環境に切り替え
k8s_env sandbox

# ArgoCDインストール
./2.deploy_argocd.sh
./3.set_nodeport.sh
./4.set_password.sh

# 動作確認
argocd-check

# 別環境に切り替え
k8s_env production

# 同じスクリプトでproduction環境にもデプロイ可能
./2.deploy_argocd.sh
```

## サンプルアプリケーション

### アプリケーション作成
```bash
./8.create_sample_app.sh
```

インタラクティブにサンプルアプリケーションを作成できます:
- ArgoCDサンプル（guestbook）
- ArgoCDサンプル（helm-guestbook）
- カスタムリポジトリ

### アプリケーション削除
```bash
./9.delete_sample_app.sh
```

### 手動操作
```bash
# ログイン（環境に応じて自動検出）
NODE_IP=$(kubectl get nodes --no-headers -o custom-columns=IP:.status.addresses[0].address | head -1)
HTTPS_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
argocd login $NODE_IP:$HTTPS_PORT --username admin --password jaileon02 --insecure

# アプリケーション作成
argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated

# アプリケーション一覧
argocd app list

# アプリケーション詳細
argocd app get guestbook

# アプリケーション同期
argocd app sync guestbook

# アプリケーション削除
argocd app delete guestbook
```

## トラブルシューティング

### 環境が切り替わらない
```bash
source ~/.bashrc
k8s_env
```

### ArgoCDにアクセスできない
```bash
# 詳細確認
./5.check_after_install.sh

# Podログ確認
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50

# Service確認
kubectl get svc -n argocd
kubectl describe svc argocd-server -n argocd
```

### パスワードを忘れた
```bash
# パスワードリセット
./4.set_password.sh
```

## アクセス情報

- **Web UI**: https://<NODE_IP>:32443
- **ユーザー名**: admin
- **パスワード**: jaileon02（デフォルト）

## 注意事項

- 本番環境では必ずパスワードを変更してください
- NodePortはファイアウォール設定を確認してください
- 複数環境で同時にArgoCDを運用する場合は、それぞれ独立したクラスターで実行してください

## ライセンス

MIT License

## 作成者

JAIST Infrastructure Team
