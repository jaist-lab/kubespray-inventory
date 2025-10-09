#!/bin/bash
# Development環境 SSH公開鍵配布

NODES="172.16.100.121 172.16.100.122 172.16.100.123 172.16.100.131 172.16.100.132 172.16.100.133"
USER="jaist-lab"
PASSWORD="jaileon02"  # 初回接続用パスワード

echo "=========================================="
echo "Development環境 SSH公開鍵配布"
echo "=========================================="
echo ""

# sshpassインストール確認
if ! command -v sshpass &> /dev/null; then
    echo "sshpassをインストール中..."
    sudo apt install -y sshpass
fi

for node in $NODES; do
    echo "配布中: ${USER}@${node}"
    
    # 既存のknown_hostsエントリを削除
    ssh-keygen -R ${node} 2>/dev/null
    
    # 公開鍵をコピー（パスワード認証で）
    sshpass -p "${PASSWORD}" ssh-copy-id -o StrictHostKeyChecking=no ${USER}@${node}
    
    if [ $? -eq 0 ]; then
        echo "✓ ${node} - 成功"
        
        # 接続テスト
        if ssh -o BatchMode=yes -o ConnectTimeout=5 ${USER}@${node} "hostname" &>/dev/null; then
            echo "  接続テスト: OK"
        else
            echo "  接続テスト: FAILED"
        fi
    else
        echo "✗ ${node} - 失敗"
    fi
    echo ""
done

echo "=========================================="
echo "配布完了"
echo "=========================================="
