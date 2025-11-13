#!/bin/bash
# 8.create_sample_app.sh
# ArgoCD サンプルアプリケーション作成（環境非依存・修正版）

set -e

echo "📱 ArgoCD サンプルアプリケーション作成"
echo "===================================="

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ArgoCD CLI確認
if ! command -v argocd >/dev/null 2>&1; then
    echo -e "${RED}❌ ArgoCD CLIがインストールされていません${NC}"
    echo ""
    echo "インストール方法:"
    echo "  ./6.install_argocd_cli_simple.sh"
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

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}❌ Kubernetesクラスターに接続できません${NC}"
    exit 1
fi

echo -e "${GREEN}✅ クラスター接続: 正常${NC}"
kubectl config current-context

# ArgoCD namespace確認
echo ""
echo "=== ArgoCD インストール確認 ==="
if ! kubectl get namespace argocd >/dev/null 2>&1; then
    echo -e "${RED}❌ ArgoCD がインストールされていません${NC}"
    echo "先にArgoCDをインストールしてください:"
    echo "  ./2.deploy_argocd.sh"
    exit 1
fi

# ArgoCD Server情報取得
SVC_TYPE=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}' 2>/dev/null)

if [ "$SVC_TYPE" != "NodePort" ]; then
    echo -e "${YELLOW}⚠️ ArgoCD ServerがNodePort型ではありません: $SVC_TYPE${NC}"
    echo "このスクリプトはNodePort型のみサポートしています"
    exit 1
fi

HTTPS_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

echo -e "${GREEN}✅ ArgoCD Server: NodePort ($HTTPS_PORT)${NC}"

# ノードIP取得（接続可能なものを検索）
echo ""
echo "=== ArgoCD Server接続先検索 ==="
NODES_INFO=$(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name,IP:.status.addresses[0].address)

SERVER=""
while read NAME IP; do
    echo -n "  $NAME ($IP:$HTTPS_PORT) -> "
    if curl -k -s --connect-timeout 3 https://$IP:$HTTPS_PORT/healthz 2>/dev/null | grep -q "ok"; then
        echo -e "${GREEN}✅${NC}"
        SERVER="$IP:$HTTPS_PORT"
        break
    else
        echo -e "${RED}❌${NC}"
    fi
done <<< "$NODES_INFO"

if [ -z "$SERVER" ]; then
    echo -e "${RED}❌ 接続可能なArgoCD Serverが見つかりません${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}接続先: https://$SERVER${NC}"

# 認証情報
echo ""
echo "=== 認証情報入力 ==="
read -p "ユーザー名 [admin]: " USERNAME
USERNAME=${USERNAME:-admin}

read -sp "パスワード [jaileon02]: " PASSWORD
echo
PASSWORD=${PASSWORD:-jaileon02}

# ArgoCD ログイン
echo ""
echo "=== ArgoCD ログイン ==="
if ! argocd login "$SERVER" \
    --username "$USERNAME" \
    --password "$PASSWORD" \
    --insecure; then
    echo -e "${RED}❌ ログインに失敗しました${NC}"
    exit 1
fi

echo -e "${GREEN}✅ ログイン成功${NC}"

# アプリケーション名とネームスペース
echo ""
echo "=== アプリケーション設定 ==="
read -p "アプリケーション名 [guestbook]: " APP_NAME
APP_NAME=${APP_NAME:-guestbook}

read -p "デプロイ先ネームスペース [default]: " DEST_NAMESPACE
DEST_NAMESPACE=${DEST_NAMESPACE:-default}

# ネームスペース作成確認
if ! kubectl get namespace "$DEST_NAMESPACE" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️ ネームスペース '$DEST_NAMESPACE' が存在しません${NC}"
    read -p "作成しますか？ (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        kubectl create namespace "$DEST_NAMESPACE"
        echo -e "${GREEN}✅ ネームスペース作成完了${NC}"
    fi
fi

# リポジトリ情報
echo ""
echo "=== Gitリポジトリ設定 ==="
echo "1. ArgoCDサンプル (guestbook)"
echo "2. ArgoCDサンプル (helm-guestbook)"
echo "3. カスタムリポジトリ"

read -p "選択 (1-3) [1]: " REPO_CHOICE
REPO_CHOICE=${REPO_CHOICE:-1}

case $REPO_CHOICE in
    1)
        REPO_URL="https://github.com/argoproj/argocd-example-apps.git"
        REPO_PATH="guestbook"
        ;;
    2)
        REPO_URL="https://github.com/argoproj/argocd-example-apps.git"
        REPO_PATH="helm-guestbook"
        ;;
    3)
        read -p "リポジトリURL: " REPO_URL
        read -p "パス: " REPO_PATH
        ;;
    *)
        echo -e "${RED}❌ 無効な選択です${NC}"
        exit 1
        ;;
esac

# アプリケーション作成確認
echo ""
echo "=== アプリケーション作成設定確認 ==="
echo "アプリケーション名: $APP_NAME"
echo "リポジトリ: $REPO_URL"
echo "パス: $REPO_PATH"
echo "デプロイ先: $DEST_NAMESPACE"
echo "クラスター: $(kubectl config current-context)"
echo ""

read -p "この設定でアプリケーションを作成しますか？ (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "キャンセルしました"
    exit 0
fi

# 既存アプリケーション確認
if argocd app get "$APP_NAME" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️ アプリケーション '$APP_NAME' は既に存在します${NC}"
    read -p "削除して再作成しますか？ (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "既存アプリケーション削除中..."
        argocd app delete "$APP_NAME" --yes
        echo "削除完了を待機中..."
        sleep 5
    else
        echo "既存のアプリケーションを使用します"
        SKIP_CREATE=true
    fi
fi

# アプリケーション作成
if [ "$SKIP_CREATE" != true ]; then
    echo ""
    echo "=== サンプルアプリケーション作成 ==="
    if argocd app create "$APP_NAME" \
        --repo "$REPO_URL" \
        --path "$REPO_PATH" \
        --dest-server https://kubernetes.default.svc \
        --dest-namespace "$DEST_NAMESPACE" \
        --sync-policy automated \
        --auto-prune \
        --self-heal; then
        echo -e "${GREEN}✅ アプリケーション作成成功${NC}"
    else
        echo -e "${RED}❌ アプリケーション作成に失敗しました${NC}"
        exit 1
    fi
fi

# アプリケーション同期
echo ""
echo "=== アプリケーション同期 ==="
if argocd app sync "$APP_NAME"; then
    echo -e "${GREEN}✅ 同期成功${NC}"
else
    echo -e "${YELLOW}⚠️ 同期に失敗しました（自動同期を待ちます）${NC}"
fi

# 同期完了待ち（修正版）
echo ""
echo "=== 同期完了待ち ==="
echo "最大3分間待機します..."

TIMEOUT=180
ELAPSED=0
LAST_HEALTH=""
LAST_SYNC=""

while [ $ELAPSED -lt $TIMEOUT ]; do
    # argocd app waitコマンドを使用（より確実）
    if argocd app wait "$APP_NAME" --timeout 10 --health 2>/dev/null; then
        echo -e "${GREEN}✅ アプリケーションがHealthy状態になりました${NC}"
        break
    fi
    
    # フォールバック: 手動でステータス確認
    APP_STATUS=$(argocd app get "$APP_NAME" --show-operation 2>/dev/null || echo "")
    HEALTH=$(echo "$APP_STATUS" | grep "Health Status:" | awk '{print $3}' || echo "Unknown")
    SYNC=$(echo "$APP_STATUS" | grep "Sync Status:" | awk '{print $3}' || echo "Unknown")
    
    # ステータスが変わった時だけ表示
    if [ "$HEALTH" != "$LAST_HEALTH" ] || [ "$SYNC" != "$LAST_SYNC" ]; then
        echo "  Health: $HEALTH, Sync: $SYNC"
        LAST_HEALTH=$HEALTH
        LAST_SYNC=$SYNC
    fi
    
    if [ "$HEALTH" = "Healthy" ] && [ "$SYNC" = "Synced" ]; then
        echo -e "${GREEN}✅ 同期完了${NC}"
        break
    elif [ "$HEALTH" = "Degraded" ]; then
        echo -e "${RED}❌ アプリケーションがDegraded状態です${NC}"
        break
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${YELLOW}⚠️ タイムアウト（3分経過）${NC}"
    echo "アプリケーションは自動同期を継続します"
fi

# アプリケーション状態確認
echo ""
echo "=== アプリケーション状態確認 ==="
argocd app get "$APP_NAME"

# リソース確認
echo ""
echo "=== デプロイされたリソース ==="
kubectl get all -n "$DEST_NAMESPACE" -l app.kubernetes.io/instance="$APP_NAME" 2>/dev/null || \
kubectl get all -n "$DEST_NAMESPACE" 2>/dev/null || \
echo "リソースが見つかりません"

# サービス確認
echo ""
echo "=== サービス確認 ==="
SERVICES=$(kubectl get svc -n "$DEST_NAMESPACE" --no-headers 2>/dev/null)
if [ -n "$SERVICES" ]; then
    kubectl get svc -n "$DEST_NAMESPACE"
    
    # NodePort型のサービスがあればアクセス情報を表示
    NODEPORT_SVCS=$(kubectl get svc -n "$DEST_NAMESPACE" -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.type=="NodePort") | .metadata.name + ":" + (.spec.ports[0].nodePort|tostring)' 2>/dev/null || \
        kubectl get svc -n "$DEST_NAMESPACE" -o jsonpath='{range .items[?(@.spec.type=="NodePort")]}{.metadata.name}:{.spec.ports[0].nodePort}{"\n"}{end}' 2>/dev/null)
    
    if [ -n "$NODEPORT_SVCS" ]; then
        echo ""
        echo "=== アクセス情報 ==="
        NODE_IP=$(echo "$SERVER" | cut -d':' -f1)
        echo "$NODEPORT_SVCS" | while read SVC_PORT; do
            SVC_NAME=$(echo "$SVC_PORT" | cut -d':' -f1)
            PORT=$(echo "$SVC_PORT" | cut -d':' -f2)
            echo "  $SVC_NAME: http://$NODE_IP:$PORT"
        done
    fi
else
    echo "サービスなし"
fi

# 完了メッセージ
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}🎉 サンプルアプリケーション作成完了！${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "ArgoCD Web UI: https://$SERVER"
echo "アプリケーション: $APP_NAME"
echo "ネームスペース: $DEST_NAMESPACE"
echo ""
echo "便利なコマンド:"
echo "  argocd app get $APP_NAME              # アプリケーション詳細"
echo "  argocd app sync $APP_NAME             # 手動同期"
echo "  argocd app logs $APP_NAME             # ログ確認"
echo "  argocd app delete $APP_NAME           # アプリケーション削除"
echo "  kubectl get all -n $DEST_NAMESPACE    # リソース確認"
echo ""
echo "📝 注意: guestbookはClusterIP型のため、クラスター外からは直接アクセスできません"
echo "    アクセスするには以下のいずれかの方法を使用してください:"
echo "    1. kubectl port-forward svc/guestbook-ui -n $DEST_NAMESPACE 8080:80"
echo "    2. Serviceを手動でNodePort型に変更"
