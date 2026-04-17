#!/bin/bash

set -e

export KUBECONFIG=~/.kube/config-development

echo "=========================================="
echo "Ingress デプロイスクリプト（Development）"
echo "=========================================="

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: 既存のIngress Controller削除
echo -e "\n${YELLOW}[Step 1]${NC} 既存のIngress Controllerを確認..."
if helm list -n ingress-nginx | grep -q ingress-nginx; then
    echo "既存のIngress Controllerを削除します..."
    helm uninstall ingress-nginx -n ingress-nginx
    sleep 5
else
    echo "既存のIngress Controllerは見つかりませんでした"
fi

# Step 2: Helmリポジトリ更新
echo -e "\n${YELLOW}[Step 2]${NC} Helmリポジトリを更新..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update

# Step 3: NGINX Ingress Controllerデプロイ
echo -e "\n${YELLOW}[Step 3]${NC} NGINX Ingress Controllerをデプロイ..."
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.hostNetwork=true \
  --set controller.kind=DaemonSet \
  --set controller.service.type=ClusterIP \
  --set controller.watchIngressWithoutClass=true

# Step 4: Podの起動待機
echo -e "\n${YELLOW}[Step 4]${NC} Ingress Controller Podの起動を待機..."
if ! kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=240s; then
    echo -e "${YELLOW}⚠️ 一部のPodが起動待機中です。状態を確認してください。${NC}"
    kubectl get pods -n ingress-nginx -o wide
fi

# Step 5: 状態確認
echo -e "\n${YELLOW}[Step 5]${NC} Ingress Controllerの状態確認..."
kubectl get pods -n ingress-nginx -o wide
kubectl get ds -n ingress-nginx

# Step 6: ArgoCD TLSシークレット作成（自己署名証明書）
echo -e "\n${YELLOW}[Step 6]${NC} ArgoCD TLSシークレットを作成..."
if ! kubectl get secret argocd-tls-secret -n argocd &>/dev/null; then
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /tmp/argocd-tls.key \
        -out /tmp/argocd-tls.crt \
        -subj "/CN=argocd.development.jaist.ac.jp/O=jaist" \
        -addext "subjectAltName=DNS:argocd.development.jaist.ac.jp"
    kubectl create secret tls argocd-tls-secret \
        --cert=/tmp/argocd-tls.crt \
        --key=/tmp/argocd-tls.key \
        -n argocd
    rm -f /tmp/argocd-tls.crt /tmp/argocd-tls.key
    echo -e "${GREEN}✓${NC} TLSシークレット作成完了"
else
    echo "既存のTLSシークレットを使用します"
fi

# Step 7: 全Ingressデプロイ（ホスト名をdevelopmentに置換して適用）
echo -e "\n${YELLOW}[Step 7]${NC} 全Ingressをデプロイ..."
sed 's/\.production\.jaist\.ac\.jp/.development.jaist.ac.jp/g' grafana-ingress.yaml     | kubectl apply -f -
sed 's/\.production\.jaist\.ac\.jp/.development.jaist.ac.jp/g' prometheus-ingress.yaml  | kubectl apply -f -
sed 's/\.production\.jaist\.ac\.jp/.development.jaist.ac.jp/g' alertmanager-ingress.yaml | kubectl apply -f -
sed 's/\.production\.jaist\.ac\.jp/.development.jaist.ac.jp/g' argocd-ingress.yaml      | kubectl apply -f -

# 設定反映待機
echo "設定反映を待機中..."
sleep 5

# Step 8: Ingress確認
echo -e "\n${YELLOW}[Step 8]${NC} Ingressの状態確認..."
echo "--- monitoring namespace ---"
kubectl get ingress -n monitoring
echo ""
echo "--- argocd namespace ---"
kubectl get ingress -n argocd

# Step 9: NodeのIP取得
echo -e "\n${YELLOW}[Step 9]${NC} NodeのIPアドレス取得..."
NODE01_IP=$(kubectl get node dev-node01 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODE02_IP=$(kubectl get node dev-node02 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
echo "dev-node01 IP: $NODE01_IP"
echo "dev-node02 IP: $NODE02_IP"

# Step 10: アクセステスト
echo -e "\n${YELLOW}[Step 10]${NC} アクセステスト..."
for HOST in grafana.development.jaist.ac.jp prometheus.development.jaist.ac.jp alertmanager.development.jaist.ac.jp; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $HOST" http://$NODE01_IP)
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ]; then
        echo -e "${GREEN}✓${NC} $HOST: HTTP $HTTP_CODE"
    else
        echo -e "${RED}✗${NC} $HOST: HTTP $HTTP_CODE"
    fi
done

# ArgoCD はHTTPSでテスト
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -H "Host: argocd.development.jaist.ac.jp" https://$NODE01_IP)
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ]; then
    echo -e "${GREEN}✓${NC} argocd.development.jaist.ac.jp: HTTPS $HTTP_CODE"
else
    echo -e "${RED}✗${NC} argocd.development.jaist.ac.jp: HTTPS $HTTP_CODE"
fi

# 完了メッセージ
echo ""
echo "=========================================="
echo -e "${GREEN}デプロイ完了${NC}"
echo "=========================================="
echo ""
echo "クライアント側の設定:"
echo "以下の行を /etc/hosts に追加してください:"
echo ""
echo "$NODE01_IP  grafana.development.jaist.ac.jp"
echo "$NODE01_IP  prometheus.development.jaist.ac.jp"
echo "$NODE01_IP  alertmanager.development.jaist.ac.jp"
echo "$NODE01_IP  argocd.development.jaist.ac.jp"
echo ""
echo "アクセスURL:"
echo "  Grafana      : http://grafana.development.jaist.ac.jp"
echo "  Prometheus   : http://prometheus.development.jaist.ac.jp"
echo "  Alertmanager : http://alertmanager.development.jaist.ac.jp"
echo "  ArgoCD       : https://argocd.development.jaist.ac.jp"
echo ""
