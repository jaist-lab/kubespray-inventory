#!/bin/bash
# 9.delete_sample_app.sh
# ArgoCD アプリケーション削除（環境非依存）

set -e

echo "🗑️  ArgoCD アプリケーション削除"
echo "=============================="

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ArgoCD CLI確認
if ! command -v argocd >/dev/null 2>&1; then
    echo -e "${RED}❌ ArgoCD CLIがインストールされていません${NC}"
    exit 1
fi

# Kubernetes環境確認
echo "=== Kubernetes環境確認 ==="
if [ -n "$KUBECONFIG" ]; then
    echo "KUBECONFIG: $KUBECONFIG"
    echo "クラスター: ${K8S_CLUSTER:-不明}"
else
    echo "KUBECONFIG: ~/.kube/config (デフォルト)"
fi

kubectl config current-context

# ArgoCD Server接続確認
HTTPS_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null)

if [ -z "$HTTPS_PORT" ]; then
    echo -e "${RED}❌ ArgoCD Serverが見つかりません${NC}"
    exit 1
fi

# 接続可能なノード検索
NODES_IPS=$(kubectl get nodes --no-headers -o custom-columns=IP:.status.addresses[0].address)
SERVER=""

for IP in $NODES_IPS; do
    if curl -k -s --connect-timeout 3 https://$IP:$HTTPS_PORT/healthz 2>/dev/null | grep -q "ok"; then
        SERVER="$IP:$HTTPS_PORT"
        break
    fi
done

if [ -z "$SERVER" ]; then
    echo -e "${RED}❌ ArgoCD Serverに接続できません${NC}"
    exit 1
fi

# ログイン確認
echo ""
echo "=== ArgoCD ログイン確認 ==="
if ! argocd app list >/dev/null 2>&1; then
    echo "ログインが必要です"
    read -p "ユーザー名 [admin]: " USERNAME
    USERNAME=${USERNAME:-admin}
    read -sp "パスワード [jaileon02]: " PASSWORD
    echo
    PASSWORD=${PASSWORD:-jaileon02}
    
    argocd login "$SERVER" --username "$USERNAME" --password "$PASSWORD" --insecure
fi

# アプリケーション一覧表示
echo ""
echo "=== アプリケーション一覧 ==="
APPS=$(argocd app list -o name 2>/dev/null)

if [ -z "$APPS" ]; then
    echo "アプリケーションが存在しません"
    exit 0
fi

echo "$APPS" | nl

# アプリケーション選択
echo ""
read -p "削除するアプリケーション名を入力してください: " APP_NAME

if [ -z "$APP_NAME" ]; then
    echo "キャンセルしました"
    exit 0
fi

# アプリケーション存在確認
if ! argocd app get "$APP_NAME" >/dev/null 2>&1; then
    echo -e "${RED}❌ アプリケーション '$APP_NAME' が見つかりません${NC}"
    exit 1
fi

# アプリケーション詳細表示
echo ""
echo "=== アプリケーション詳細 ==="
argocd app get "$APP_NAME"

# 削除確認
echo ""
echo -e "${YELLOW}⚠️  以下のアプリケーションを削除します:${NC}"
echo "  アプリケーション: $APP_NAME"

DEST_NS=$(argocd app get "$APP_NAME" -o json | jq -r '.spec.destination.namespace' 2>/dev/null)
if [ -n "$DEST_NS" ]; then
    echo "  ネームスペース: $DEST_NS"
fi

echo ""
read -p "本当に削除しますか？ (yes/NO): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "キャンセルしました"
    exit 0
fi

# アプリケーション削除
echo ""
echo "=== アプリケーション削除実行 ==="
if argocd app delete "$APP_NAME" --yes; then
    echo -e "${GREEN}✅ アプリケーション削除成功${NC}"
else
    echo -e "${RED}❌ アプリケーション削除に失敗しました${NC}"
    exit 1
fi

# リソース確認
if [ -n "$DEST_NS" ]; then
    echo ""
    echo "=== 残存リソース確認 ==="
    REMAINING=$(kubectl get all -n "$DEST_NS" 2>/dev/null | grep -v "^NAME" | wc -l)
    
    if [ "$REMAINING" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  ネームスペース '$DEST_NS' にリソースが残っています${NC}"
        kubectl get all -n "$DEST_NS"
        
        echo ""
        read -p "ネームスペース '$DEST_NS' を削除しますか？ (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete namespace "$DEST_NS"
            echo -e "${GREEN}✅ ネームスペース削除完了${NC}"
        fi
    else
        echo "残存リソースなし"
    fi
fi

echo ""
echo -e "${GREEN}✅ 削除完了${NC}"
