#!/bin/bash
echo ""
echo "🔧 ArgoCD Server NodePort設定"
echo "============================"

# ArgoCD ServerをNodePortに変更
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"protocol":"TCP","targetPort":8080,"nodePort":32443}]}}'

echo ""
echo "=== Service設定確認 ==="
kubectl get svc argocd-server -n argocd

echo ""
echo "✅ NodePort設定完了"
`
