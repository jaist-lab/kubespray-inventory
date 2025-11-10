#!/bin/bash
# complete_clean_install.sh

echo "☢️ 完全クリーンインストール"
echo "=========================="

export KUBECONFIG="$HOME/.kube/config-production"

echo "⚠️ ArgoCDを完全削除して再インストールします"
read -p "続行しますか？ (yes/NO): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    exit 0
fi

# 1. 完全削除
echo ""
echo "=== 削除 ==="
kubectl delete namespace argocd --force --grace-period=0

echo "削除待ち（60秒）..."
sleep 60

# namespace強制削除
kubectl get namespace argocd 2>/dev/null && kubectl patch namespace argocd -p '{"metadata":{"finalizers":[]}}' --type=merge

# 2. 再インストール
echo ""
echo "=== 再インストール ==="
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. NetworkPolicy削除
echo ""
echo "=== NetworkPolicy削除 ==="
sleep 20
kubectl delete networkpolicies --all -n argocd

# 4. Pod起動待ち
echo ""
echo "=== Pod起動待ち ==="
for i in {1..30}; do
    RUNNING=$(kubectl get pods -n argocd --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    echo "  チェック $i/30: $RUNNING Pods Running"
    
    if [ "$RUNNING" -ge 7 ]; then
        echo "  ✅ 全Pod起動"
        break
    fi
    sleep 10
done

kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd

# 5. NodePort & Password
echo ""
echo "=== NodePort設定 ==="
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"protocol":"TCP","targetPort":8080,"nodePort":32443}]}}'

echo ""
echo "=== パスワード設定 ==="
kubectl -n argocd patch secret argocd-secret -p '{"stringData": {"admin.password": "$2a$10$rRyBsGSHK6.uc8fntPwVIuLVHgsAhAX7TcdrqW/RADU0uh7CaChLa","admin.passwordMtime": "'$(date +%FT%T%Z)'"}}'

# 6. 最終待機
echo ""
echo "=== 最終安定化（90秒） ==="
sleep 90

echo ""
echo "=== 状態確認 ==="
kubectl get pods -n argocd
kubectl get svc -n argocd | grep -E "NAME|server|repo|redis"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 完了"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
