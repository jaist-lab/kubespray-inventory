#!/bin/bash
# deep_diagnosis.sh
# 徹底的な診断

echo "🔬 徹底診断"
echo "=========="

k8s_env production

echo "=== 1. Pod詳細状態 ==="
kubectl get pods -n argocd -o wide

echo ""
echo "=== 2. Service & Endpoints ==="
echo "Repo Server Service:"
kubectl get svc argocd-repo-server -n argocd -o yaml | grep -A 10 "spec:"

echo ""
echo "Repo Server Endpoints:"
kubectl get endpoints argocd-repo-server -n argocd -o yaml

echo ""
echo "=== 3. NetworkPolicy再確認 ==="
NP_COUNT=$(kubectl get networkpolicies -n argocd --no-headers 2>/dev/null | wc -l)
echo "NetworkPolicy数: $NP_COUNT"
if [ $NP_COUNT -gt 0 ]; then
    echo "⚠️ NetworkPolicyがまだ存在します！"
    kubectl get networkpolicies -n argocd
fi

echo ""
echo "=== 4. argocd-server Podからの接続テスト ==="
ARGOCD_SERVER_POD=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers | head -1 | awk '{print $1}')
REPO_POD=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server --no-headers | head -1 | awk '{print $1}')

echo "ArgoCD Server Pod: $ARGOCD_SERVER_POD"
echo "Repo Server Pod: $REPO_POD"

REPO_SERVICE_IP=$(kubectl get svc argocd-repo-server -n argocd -o jsonpath='{.spec.clusterIP}')
REPO_POD_IP=$(kubectl get pod $REPO_POD -n argocd -o jsonpath='{.status.podIP}')

echo "Repo Service ClusterIP: $REPO_SERVICE_IP"
echo "Repo Pod IP: $REPO_POD_IP"

echo ""
echo "=== 5. 直接Pod IPへの接続テスト ==="
echo "テスト: argocd-server → repo-server Pod IP"
kubectl exec -n argocd $ARGOCD_SERVER_POD -- timeout 5 sh -c "cat < /dev/null > /dev/tcp/$REPO_POD_IP/8081" 2>&1 && echo "✅ Pod IP接続: 成功" || echo "❌ Pod IP接続: 失敗"

echo ""
echo "=== 6. Service IP経由の接続テスト ==="
echo "テスト: argocd-server → repo-server Service IP"
kubectl exec -n argocd $ARGOCD_SERVER_POD -- timeout 5 sh -c "cat < /dev/null > /dev/tcp/$REPO_SERVICE_IP/8081" 2>&1 && echo "✅ Service IP接続: 成功" || echo "❌ Service IP接続: 失敗"

echo ""
echo "=== 7. Repo Serverが実際にリッスンしているか ==="
echo "Repo Server内部からのテスト:"
kubectl exec -n argocd $REPO_POD -- timeout 5 sh -c "cat < /dev/null > /dev/tcp/localhost/8081" 2>&1 && echo "✅ localhost:8081: リッスン中" || echo "❌ localhost:8081: リッスンしていない"

echo ""
echo "=== 8. Repo Serverプロセス確認 ==="
kubectl exec -n argocd $REPO_POD -- ps aux | grep argocd-repo-server || echo "プロセス確認失敗"

echo ""
echo "=== 9. Repo Serverログ ==="
kubectl logs -n argocd $REPO_POD --tail=20

echo ""
echo "=== 10. argocd-serverログ（repo関連エラー） ==="
kubectl logs -n argocd $ARGOCD_SERVER_POD --tail=50 | grep -i "repo\|8081\|timeout" || echo "関連ログなし"

echo ""
echo "=== 11. Calico/iptables確認 ==="
# kube-proxyのモード確認
kubectl get configmap -n kube-system kube-proxy -o yaml | grep mode || echo "kube-proxy mode確認失敗"

echo ""
echo "=== 12. 同じノードに配置されているか ==="
SERVER_NODE=$(kubectl get pod $ARGOCD_SERVER_POD -n argocd -o jsonpath='{.spec.nodeName}')
REPO_NODE=$(kubectl get pod $REPO_POD -n argocd -o jsonpath='{.spec.nodeName}')

echo "argocd-server: $SERVER_NODE"
echo "repo-server: $REPO_NODE"

if [ "$SERVER_NODE" = "$REPO_NODE" ]; then
    echo "✅ 同じノード（ネットワーク問題の可能性低）"
else
    echo "⚠️ 異なるノード（ノード間通信問題の可能性）"
fi
