#!/bin/bash
# ArgoCD 管理者パスワード設定

echo ""
echo "🔐 ArgoCD 管理者パスワード設定"
echo "======================================"

# デフォルトパスワード確認（リトライ機能付き）
echo "=== デフォルトパスワード確認 ==="
RETRY_COUNT=0
MAX_RETRIES=10

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    DEFAULT_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null)
    
    if [ -n "$DEFAULT_PASSWORD" ] && [ ${#DEFAULT_PASSWORD} -gt 5 ]; then
        echo "✅ デフォルトパスワード取得成功: $DEFAULT_PASSWORD"
        break
    else
        echo "⏳ デフォルトパスワード生成待ち... (試行 $((RETRY_COUNT + 1))/$MAX_RETRIES)"
        sleep 10
        RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
done

if [ -z "$DEFAULT_PASSWORD" ]; then
    echo "❌ デフォルトパスワードの取得に失敗しました"
    echo "手動でパスワードを確認してください:"
    echo "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    exit 1
fi

# 新しいパスワード設定
echo ""
echo "=== 新しいパスワード設定 ==="
NEW_PASSWORD="j4157Adm!n"

# bcryptハッシュ生成（改良版）
echo "bcryptハッシュ生成中..."

# 一時的なPodでbcryptハッシュ生成（エラーハンドリング付き）
HASHED_PASSWORD=$(kubectl run bcrypt-hasher-$(date +%s) --rm -i --restart=Never --image=python:3.9-slim --quiet --timeout=60s -- python3 -c "
try:
    import bcrypt
    password = '$NEW_PASSWORD'.encode('utf-8')
    salt = bcrypt.gensalt(rounds=10)
    hashed = bcrypt.hashpw(password, salt)
    print(hashed.decode('utf-8'))
except Exception as e:
    print('ERROR: ' + str(e))
    exit(1)
" 2>/dev/null)

# ハッシュ生成結果確認
if [[ "$HASHED_PASSWORD" == ERROR:* ]] || [ -z "$HASHED_PASSWORD" ]; then
    echo "❌ bcryptハッシュ生成に失敗しました"
    echo "デフォルトパスワードを使用してください: $DEFAULT_PASSWORD"
    echo ""
    echo "=== アクセス情報（デフォルトパスワード使用） ==="
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo "ArgoCD Web UI: https://$NODE_IP:32443"
    echo "ユーザー名: admin"
    echo "パスワード: $DEFAULT_PASSWORD"
    echo ""
    echo "⚠️ ログイン後、WebUIからパスワードを変更してください"
    exit 0
fi

echo "✅ bcryptハッシュ生成成功"

# argocd-secret更新（改良版）
echo "Secret更新中..."

# 現在時刻をRFC3339形式で生成
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Secret存在確認
if ! kubectl get secret argocd-secret -n argocd >/dev/null 2>&1; then
    echo "argocd-secret が存在しません。作成します..."
    kubectl create secret generic argocd-secret -n argocd
fi

# Secretパッチ適用（エラーハンドリング付き）
if kubectl -n argocd patch secret argocd-secret --type='merge' -p="{
    \"data\": {
        \"admin.password\": \"$(echo -n "$HASHED_PASSWORD" | base64 -w 0)\",
        \"admin.passwordMtime\": \"$(echo -n "$CURRENT_TIME" | base64 -w 0)\"
    }
}"; then
    echo "✅ Secret更新成功"
else
    echo "❌ Secret更新失敗"
    echo "デフォルトパスワードを使用してください: $DEFAULT_PASSWORD"
    exit 1
fi

# 初期パスワードSecret削除（オプション）
echo "初期パスワードSecret削除中..."
kubectl -n argocd delete secret argocd-initial-admin-secret --ignore-not-found=true

# ArgoCD Server Pod再起動
echo "ArgoCD Server再起動中..."
kubectl -n argocd rollout restart deployment/argocd-server

echo "再起動完了待ち..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=120s

echo ""
echo "✅ 管理者パスワード設定完了"

# 設定確認とテスト
echo ""
echo "=== 設定確認 ==="
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "ArgoCD Web UI: https://$NODE_IP:32443"
echo "ユーザー名: admin"
echo "パスワード: $NEW_PASSWORD"

# 30秒待機後にログインテスト
echo ""
echo "=== ログインテスト実行 ==="
echo "30秒待機後にログインテストを実行します..."
sleep 30

# API経由でのログインテスト
echo "ログインテスト中..."
LOGIN_RESPONSE=$(curl -k -s -w "%{http_code}" -X POST "https://$NODE_IP:32443/api/v1/session" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"admin\",\"password\":\"$NEW_PASSWORD\"}" \
    --connect-timeout 10 --max-time 30)

HTTP_CODE="${LOGIN_RESPONSE: -3}"
RESPONSE_BODY="${LOGIN_RESPONSE%???}"

if [ "$HTTP_CODE" = "200" ] && echo "$RESPONSE_BODY" | grep -q '"token"'; then
    echo "✅ 新しいパスワードでのログイン成功確認"
    echo ""
    echo "🎉 ArgoCD インストール・設定完了！"
    echo ""
    echo "=== 最終アクセス情報 ==="
    echo "ArgoCD Web UI: https://$NODE_IP:32443"
    echo "ユーザー名: admin"
    echo "新パスワード: $NEW_PASSWORD"
    echo "default パスワード: $DEFAULT_PASSWORD"
    echo ""
    echo "ℹ️ 初回アクセス時はブラウザでSSL警告が表示される場合があります"
    echo "ℹ️ Chrome/Firefox: 「詳細設定」→「安全でないサイトに進む」をクリック"
else
    echo "⚠️ ログインテストで問題が発生しました（HTTP: $HTTP_CODE）"
    echo "手動でWebUIからログインしてみてください"
    echo ""
    echo "=== フォールバック情報 ==="
    echo "デフォルトパスワード: $DEFAULT_PASSWORD"
    echo "新しいパスワード: $NEW_PASSWORD"
    echo "どちらかでログインしてみてください"
fi

echo ""
