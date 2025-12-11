#!/bin/bash
# add-etcdctl-master-nodes.sh - 全Masterノードにetcdctlをインストール

set -e

# 環境選択
echo "インストールする環境を選択してください:"
echo "  1) Production"
echo "  2) Development"
echo "  3) Sandbox"
read -p "選択 (1/2/3): " ENV_CHOICE

case $ENV_CHOICE in
    1)
        MASTER_IPS=("172.16.100.101" "172.16.100.102" "172.16.100.103")
        MASTER_NAMES=("master01" "master02" "master03")
        ;;
    2)
        MASTER_IPS=("172.16.100.121" "172.16.100.122" "172.16.100.123")
        MASTER_NAMES=("dev-master01" "dev-master02" "dev-master03")
        ;;
    3)
        MASTER_IPS=("172.16.100.131" "172.16.100.132" "172.16.100.133")
        MASTER_NAMES=("sandbox-master01" "sandbox-master02" "sandbox-master03")
        ;;
    *)
        echo "無効な選択です"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "etcdctlインストール開始"
echo "=========================================="

# インストールスクリプトを作成
cat > /tmp/install-etcdctl.sh << 'SCRIPT_EOF'
#!/bin/bash
set -e

# etcdバージョン取得
ETCD_VERSION=$(sudo /usr/local/bin/etcd --version | head -1 | awk '{print $3}')
echo "検出されたetcdバージョン: $ETCD_VERSION"

# アーキテクチャ確認
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
esac

DOWNLOAD_URL=https://github.com/etcd-io/etcd/releases/download
TARBALL="etcd-v${ETCD_VERSION}-linux-${ARCH}.tar.gz"

# ダウンロード
echo "ダウンロード中..."
curl -L ${DOWNLOAD_URL}/v${ETCD_VERSION}/${TARBALL} -o /tmp/${TARBALL}

# 展開
echo "展開中..."
tar xzvf /tmp/${TARBALL} -C /tmp --strip-components=1 etcd-v${ETCD_VERSION}-linux-${ARCH}/etcdctl

# インストール
echo "インストール中..."
sudo mv /tmp/etcdctl /usr/local/bin/
sudo chmod +x /usr/local/bin/etcdctl

# クリーンアップ
rm -f /tmp/${TARBALL}

# 確認
echo ""
echo "インストール完了:"
etcdctl version
SCRIPT_EOF

chmod +x /tmp/install-etcdctl.sh

# 各Masterノードにコピーして実行
for i in "${!MASTER_IPS[@]}"; do
    IP="${MASTER_IPS[$i]}"
    NAME="${MASTER_NAMES[$i]}"
    
    echo ""
    echo ">>> ${NAME} (${IP}) にインストール中..."
    
    # スクリプトをコピー
    scp /tmp/install-etcdctl.sh jaistlab@${IP}:/tmp/
    
    # 実行
    ssh jaistlab@${IP} "bash /tmp/install-etcdctl.sh"
    
    # クリーンアップ
    ssh jaistlab@${IP} "rm -f /tmp/install-etcdctl.sh"
    
    echo "✓ ${NAME} インストール完了"
done

# ローカルのスクリプト削除
rm -f /tmp/install-etcdctl.sh

echo ""
echo "=========================================="
echo "✓ 全Masterノードへのインストール完了"
echo "=========================================="
