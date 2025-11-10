#!/bin/bash
# 6.install_argocd_cli_simple.sh
# ArgoCD CLI 簡易インストールスクリプト

set -e

# 最新版を/usr/local/binにインストール
echo "🔧 ArgoCD CLI インストール開始..."

# OS/ARCH検出
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] && ARCH="amd64"
[ "$ARCH" = "aarch64" ] && ARCH="arm64"

# 最新版取得
VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep '"tag_name"' | cut -d'"' -f4)

# ダウンロード＆インストール
curl -sSL -o /tmp/argocd "https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-${OS}-${ARCH}"
chmod +x /tmp/argocd
sudo install -m 555 /tmp/argocd /usr/local/bin/argocd
rm /tmp/argocd

echo "✅ インストール完了"
argocd version --client
