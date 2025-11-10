#!/bin/bash
# ArgoCD 簡易パスワード設定（推奨方法）

echo "🔐 ArgoCD 簡易パスワード設定"
echo "=========================="

# ArgoCD CLIインストール（临时）
echo "=== ArgoCD CLI一時インストール ==="
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# ArgoCD サーバーにログイン（デフォルトパスワード使用）
echo ""
echo "=== ArgoCD ログイン ==="
NODE_IP=$(kubectl get nodes node101 -o jsonpath='{.status.addresses[0].address}' 2>/dev/null)
DEFAULT_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# サーバー証明書確認をスキップしてログイン
argocd login $NODE_IP:32443 --username admin --password $DEFAULT_PASSWORD --insecure

# パスワード変更
echo ""
echo "=== パスワード変更 ==="
argocd account update-password --current-password $DEFAULT_PASSWORD --new-password jaileon02

echo ""
echo "✅ パスワード変更完了"
echo "新しいログイン情報:"
echo "  ユーザー名: admin"
echo "  パスワード: jaileon02"
echo "  URL: https://$NODE_IP:32443"

# 初期シークレット削除（推奨）
kubectl -n argocd delete secret argocd-initial-admin-secret

echo ""
echo "✅ 初期設定完了"
