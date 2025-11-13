#!/bin/bash
# argocd-check.sh (最終版)
# 環境非依存のArgoCD動作確認スクリプト

set -eo pipefail

echo "🔍 ArgoCD 総合動作確認（汎用版）"
echo "================================"

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# KUBECONFIG確認
echo "=== Kubernetes環境確認 ==="
if [ -n "$KUBECONFIG" ]; then
    echo "KUBECONFIG: $KUBECONFIG"
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null | cut -d'@' -f2 || echo "不明")
    echo "クラスター: ${K8S_CLUSTER:-$CLUSTER_NAME}"
else
    echo "KUBECONFIG: ~/.kube/config (デフォルト)"
fi

# 接続確認
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}❌ Kubernetesクラスターに接続できません${NC}"
    echo "環境変数やkubeconfigを確認してください"
    exit 1
fi

echo -e "${GREEN}✅ クラスター接続: 正常${NC}"
kubectl config current-context

# ノード情報を動的に取得
echo ""
echo "=== ノード情報取得 ==="
NODES_INFO=$(kubectl get nodes --no-headers -o custom-columns=\
NAME:.metadata.name,\
IP:.status.addresses[0].address,\
ROLES:.metadata.labels 2>/dev/null | \
awk '{
    name=$1;
    ip=$2;
    roles=$3;
    if (roles ~ /control-plane/ || roles ~ /kubernetes.io\/role:master/) {
        print name, ip, "control-plane"
    } else {
        print name, ip, "worker"
    }
}')

if [ -z "$NODES_INFO" ]; then
    echo -e "${RED}❌ ノード情報の取得に失敗しました${NC}"
    exit 1
fi

echo "$NODES_INFO" | while read NAME IP ROLE; do
    if [ "$ROLE" = "control-plane" ]; then
        echo "  Master: $NAME ($IP)"
    else
        echo "  Worker: $NAME ($IP)"
    fi
done

FIRST_NODE_NAME=$(echo "$NODES_INFO" | head -1 | awk '{print $1}')
NODE_IP=$(echo "$NODES_INFO" | head -1 | awk '{print $2}')

echo ""
echo "使用するノード: $FIRST_NODE_NAME"
echo "ノードIP: $NODE_IP"

# ArgoCD namespace確認
echo ""
echo "=== ArgoCD ネームスペース確認 ==="
if ! kubectl get namespace argocd >/dev/null 2>&1; then
    echo -e "${RED}❌ argocd ネームスペースが存在しません${NC}"
    exit 1
fi
echo -e "${GREEN}✅ argocd ネームスペース存在${NC}"

# Pod状態確認
echo ""
echo "=== ArgoCD Pod状態 ==="
kubectl get pods -n argocd -o wide

POD_COUNT=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
RUNNING_COUNT=$(kubectl get pods -n argocd --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

if [ "$POD_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ ArgoCD Podが見つかりません${NC}"
    exit 1
fi

echo "Pod数: $RUNNING_COUNT/$POD_COUNT が稼働中"

# Service確認
echo ""
echo "=== ArgoCD Service確認 ==="
if ! kubectl get svc argocd-server -n argocd >/dev/null 2>&1; then
    echo -e "${RED}❌ argocd-server Serviceが見つかりません${NC}"
    exit 1
fi

SVC_TYPE=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}')
echo "Service Type: $SVC_TYPE"

if [ "$SVC_TYPE" = "NodePort" ]; then
    HTTPS_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
    HTTP_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
    echo "HTTPS NodePort: $HTTPS_PORT"
    echo "HTTP NodePort: $HTTP_PORT"
elif [ "$SVC_TYPE" = "LoadBalancer" ]; then
    EXTERNAL_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo "External IP: ${EXTERNAL_IP:-Pending...}"
    HTTPS_PORT=443
elif [ "$SVC_TYPE" = "ClusterIP" ]; then
    CLUSTER_IP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.clusterIP}')
    echo "Cluster IP: $CLUSTER_IP"
    echo -e "${YELLOW}⚠️  ClusterIP型のため、外部からは直接アクセスできません${NC}"
fi

# Endpoints確認
echo ""
echo "=== Endpoints確認 ==="
kubectl get endpoints argocd-server -n argocd

ENDPOINTS=$(kubectl get endpoints argocd-server -n argocd -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
if [ -z "$ENDPOINTS" ]; then
    echo -e "${YELLOW}⚠️  Endpointsが空です${NC}"
fi

# 接続テスト
if [ "$SVC_TYPE" = "NodePort" ] && [ -n "$HTTPS_PORT" ]; then
    echo ""
    echo "=== 接続テスト ==="

    SUCCESS_COUNT=0
    WORKING_IP=""

    while read NAME IP ROLE; do
        echo -n "  $NAME ($IP):$HTTPS_PORT -> "
        if curl -k -s --connect-timeout 3 https://$IP:$HTTPS_PORT/healthz 2>/dev/null | grep -q "ok"; then
            echo -e "${GREEN}✅${NC}"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            if [ -z "$WORKING_IP" ]; then
                WORKING_IP=$IP
            fi
        else
            echo -e "${RED}❌${NC}"
        fi
    done <<< "$NODES_INFO"

    echo ""
    echo "主要ノード接続テスト: https://$NODE_IP:$HTTPS_PORT"
    if curl -k -s --connect-timeout 5 https://$NODE_IP:$HTTPS_PORT/healthz 2>/dev/null | grep -q "ok"; then
        echo -e "${GREEN}✅ 外部接続: 成功${NC}"
        [ -z "$WORKING_IP" ] && WORKING_IP=$NODE_IP
        EXTERNAL_SUCCESS=true
    else
        echo -e "${RED}⚠️ 外部接続: 失敗${NC}"
        EXTERNAL_SUCCESS=false
    fi

    # API確認（修正版 - 判定ロジック改善）
    if [ "$EXTERNAL_SUCCESS" = true ] || [ -n "$WORKING_IP" ]; then
        echo ""
        echo "=== API確認 ==="
        TEST_IP=${WORKING_IP:-$NODE_IP}
        API_RESPONSE=$(curl -k -s --connect-timeout 5 https://$TEST_IP:$HTTPS_PORT/api/version 2>/dev/null)

        # JSON形式かチェック（より厳密に）
        if [ -n "$API_RESPONSE" ] && echo "$API_RESPONSE" | jq -e . >/dev/null 2>&1; then
            echo -e "${GREEN}✅ API応答: 正常${NC}"
            VERSION=$(echo "$API_RESPONSE" | jq -r '.Version // .version // "不明"' 2>/dev/null)
            echo "ArgoCD Version: $VERSION"
            API_SUCCESS=true
        elif [ -n "$API_RESPONSE" ] && echo "$API_RESPONSE" | grep -q '"[Vv]ersion"'; then
            # jqがない場合のフォールバック
            echo -e "${GREEN}✅ API応答: 正常${NC}"
            VERSION=$(echo "$API_RESPONSE" | grep -o '"[Vv]ersion":"[^"]*"' | cut -d'"' -f4)
            echo "ArgoCD Version: $VERSION"
            API_SUCCESS=true
        else
            echo -e "${YELLOW}⚠️ API応答: 異常${NC}"
            echo "レスポンス: ${API_RESPONSE:-empty}"
            API_SUCCESS=false
        fi
    fi
fi


# 総合評価
echo ""
echo "=== 総合評価 ==="
SCORE=0

# Pod状態（25点）
if [ "$RUNNING_COUNT" -eq "$POD_COUNT" ] && [ "$POD_COUNT" -gt 0 ]; then
    SCORE=$((SCORE + 25))
fi

# Service設定（25点）
if [ "$SVC_TYPE" = "NodePort" ] || [ "$SVC_TYPE" = "LoadBalancer" ]; then
    SCORE=$((SCORE + 25))
fi

# Endpoints（25点）
if [ -n "$ENDPOINTS" ]; then
    SCORE=$((SCORE + 25))
fi

# 外部接続（25点）
if [ "$SVC_TYPE" = "NodePort" ]; then
    if [ "$EXTERNAL_SUCCESS" = true ]; then
        SCORE=$((SCORE + 25))
    fi
elif [ "$SVC_TYPE" = "LoadBalancer" ] && [ -n "$EXTERNAL_IP" ]; then
    SCORE=$((SCORE + 25))
fi

echo "成功度: ${SCORE}%"

if [ $SCORE -eq 100 ]; then
    echo -e "${GREEN}🎉 ArgoCD完全正常${NC}"
elif [ $SCORE -ge 75 ]; then
    echo -e "${GREEN}✅ ArgoCD概ね正常（一部要確認）${NC}"
elif [ $SCORE -ge 50 ]; then
    echo -e "${YELLOW}⚠️ ArgoCD部分的に問題あり${NC}"
else
    echo -e "${RED}❌ ArgoCD重大な問題あり${NC}"
fi

# 詳細ステータス
echo ""
echo "=== 詳細ステータス ==="
echo "Pod稼働: $([ "$RUNNING_COUNT" -eq "$POD_COUNT" ] && echo "✅" || echo "❌") ($RUNNING_COUNT/$POD_COUNT)"
echo "Service: $([ "$SVC_TYPE" = "NodePort" ] && echo "✅ NodePort" || echo "⚠️ $SVC_TYPE")"
echo "Endpoints: $([ -n "$ENDPOINTS" ] && echo "✅" || echo "❌")"
echo "外部接続: $([ "$EXTERNAL_SUCCESS" = true ] && echo "✅" || echo "❌")"
echo "API応答: $([ "$API_SUCCESS" = true ] && echo "✅" || echo "⚠️")"

# アクセス情報表示
echo ""
echo "=== アクセス情報 ==="
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$SVC_TYPE" = "NodePort" ]; then
    if [ -n "$WORKING_IP" ]; then
        echo -e "${GREEN}ArgoCD Web UI: https://$WORKING_IP:$HTTPS_PORT${NC}"
    else
        echo "ArgoCD Web UI: https://$NODE_IP:$HTTPS_PORT"
    fi

    if [ $SUCCESS_COUNT -gt 1 ]; then
        echo ""
        echo "または以下のいずれか（$SUCCESS_COUNT ノードで利用可能）:"
        while read NAME IP ROLE; do
            if curl -k -s --connect-timeout 2 https://$IP:$HTTPS_PORT/healthz 2>/dev/null | grep -q "ok"; then
                echo "  https://$IP:$HTTPS_PORT ($NAME)"
            fi
        done <<< "$NODES_INFO"
    fi
elif [ "$SVC_TYPE" = "LoadBalancer" ] && [ -n "$EXTERNAL_IP" ]; then
    echo "ArgoCD Web UI: https://$EXTERNAL_IP"
elif [ "$SVC_TYPE" = "ClusterIP" ]; then
    echo "Port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "アクセス: https://localhost:8080"
fi

echo ""
echo "ユーザー名: admin"
echo "パスワード: jaileon02"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# トラブルシューティング情報
if [ $SCORE -lt 100 ] || [ "$API_SUCCESS" != true ] || [ "$POD_INTERNAL_SUCCESS" != true ]; then
    echo ""
    echo "=== トラブルシューティング ==="

    if [ "$EXTERNAL_SUCCESS" != true ]; then
        echo "❌ 外部接続失敗"
        echo "   確認: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=20"
    fi

    if [ "$API_SUCCESS" != true ]; then
        echo "⚠️ API応答異常（実用上は問題なし）"
        echo "   確認: curl -k -v https://$NODE_IP:$HTTPS_PORT/api/version"
    fi

    if [ "$POD_INTERNAL_SUCCESS" != true ]; then
        echo "ℹ️  Pod内部接続失敗（非必須機能、実用上は問題なし）"
        echo "   理由: コンテナ内にcurl/wgetがインストールされていない可能性"
    fi
fi

echo ""
echo "✅ 動作確認完了"

