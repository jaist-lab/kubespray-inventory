#!/bin/bash

set -e

echo "=========================================="
echo "Grafana Ingress デプロイスクリプト"
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
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Step 5: 状態確認
echo -e "\n${YELLOW}[Step 5]${NC} Ingress Controllerの状態確認..."
kubectl get pods -n ingress-nginx -o wide
kubectl get ds -n ingress-nginx

# Step 6: Grafana Ingressデプロイ
echo -e "\n${YELLOW}[Step 6]${NC} Grafana Ingressをデプロイ..."
kubectl apply -f grafana-ingress.yaml

# 設定反映待機
echo "設定反映を待機中..."
sleep 5

# Step 7: Ingress確認
echo -e "\n${YELLOW}[Step 7]${NC} Ingressの状態確認..."
kubectl get ingress -n monitoring
echo ""
kubectl describe ingress grafana-ingress -n monitoring

# Step 8: NodeのIP取得
echo -e "\n${YELLOW}[Step 8]${NC} NodeのIPアドレス取得..."
NODE01_IP=$(kubectl get node node01 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
NODE02_IP=$(kubectl get node node02 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
echo "Node01 IP: $NODE01_IP"
echo "Node02 IP: $NODE02_IP"

# Step 9: アクセステスト
echo -e "\n${YELLOW}[Step 9]${NC} アクセステスト..."
echo "Testing via node01..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: grafana.production.jaist.ac.jp" http://$NODE01_IP)
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ]; then
    echo -e "${GREEN}✓${NC} HTTP Status: $HTTP_CODE (Success)"
else
    echo -e "${RED}✗${NC} HTTP Status: $HTTP_CODE (Failed)"
fi

echo ""
echo "Testing via node02..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: grafana.production.jaist.ac.jp" http://$NODE02_IP)
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ]; then
    echo -e "${GREEN}✓${NC} HTTP Status: $HTTP_CODE (Success)"
else
    echo -e "${RED}✗${NC} HTTP Status: $HTTP_CODE (Failed)"
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
echo "$NODE01_IP  grafana.production.jaist.ac.jp"
echo ""
echo "アクセスURL:"
echo "http://grafana.production.jaist.ac.jp"
echo ""
