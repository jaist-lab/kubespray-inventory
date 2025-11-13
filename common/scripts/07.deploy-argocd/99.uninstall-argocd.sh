#!/bin/bash
# ArgoCD クイックアンインストール

echo "🗑️ ArgoCD アンインストール開始"
echo "=============================="

# 確認プロンプト
read -p "ArgoCD を完全に削除しますか？ (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "アンインストールをキャンセルしました"
    exit 0
fi

echo ""
echo "=== ArgoCD アプリケーション確認 ==="
kubectl get applications -n argocd 2>/dev/null || echo "アプリケーションなし"

# アプリケーションが存在する場合の警告
APP_COUNT=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
if [ "$APP_COUNT" -gt 0 ]; then
    echo "⚠️  警告: $APP_COUNT 個のアプリケーションが存在します"
    kubectl get applications -n argocd
    echo ""
    read -p "これらのアプリケーションも削除されます。続行しますか？ (yes/no): " APP_CONFIRM
    if [ "$APP_CONFIRM" != "yes" ]; then
        echo "アンインストールをキャンセルしました"
        exit 0
    fi
fi

echo ""
echo "=== argocd ネームスペース削除 ==="
kubectl delete namespace argocd

echo ""
echo "=== 削除完了待ち ==="
echo "（ネームスペース削除には1-3分程度かかる場合があります）"

# ネームスペース削除完了を待つ
TIMEOUT=180
ELAPSED=0
while kubectl get namespace argocd >/dev/null 2>&1; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "⚠️  タイムアウト: ネームスペース削除に時間がかかっています"
        echo "バックグラウンドで削除処理が続いています"
        break
    fi
    echo -n "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""
echo ""
echo "=== 削除確認 ==="
if kubectl get namespace argocd >/dev/null 2>&1; then
    echo "⚠️  argocd ネームスペースがまだ存在しています（削除処理中）"
else
    echo "✅ argocd ネームスペース削除完了"
fi

echo ""
echo "=== ArgoCD CLI確認 ==="
if command -v argocd >/dev/null 2>&1; then
    echo "ℹ️  ArgoCD CLIがインストールされています"
    read -p "ArgoCD CLIも削除しますか？ (yes/no): " CLI_CONFIRM
    if [ "$CLI_CONFIRM" = "yes" ]; then
        sudo rm -f /usr/local/bin/argocd
        echo "✅ ArgoCD CLI削除完了"
    else
        echo "ArgoCD CLIは残されました"
    fi
else
    echo "ArgoCD CLI未インストール"
fi

echo ""
echo "✅ ArgoCD アンインストール完了"
