# Kubespray Inventory Configuration

このリポジトリは、KubernetesクラスタのInventory設定を管理します。

## 環境

- **Production**: 3 Master + 3 Worker (172.16.100.101-113)
- **Development**: 3 Master + 3 Worker (172.16.100.121-133)

## 使用方法

まずkubesprayのリポジトリを取得します
```bash
mkdir ~/kubernetes
cd ~/kubernetes
git clone https://github.com/kubernetes-sigs/kubespray.git
```

```bash
# Kubesprayディレクトリ内でこのリポジトリをシンボリックリンク
cd ~/kubernetes/kubespray
ln -s ~/kubernetes/kubespray-inventory inventory

# デプロイ実行
cd ~/kubernetes/kubespray
source ~/kubernetes/venv/bin/activate
ansible-playbook -i inventory/production/hosts.yml cluster.yml
```

## ディレクトリ構造

```
.
├── production/          # 本番環境
│   ├── hosts.yml
│   └── group_vars/
├── development/         # 開発環境
│   ├── hosts.yml
│   └── group_vars/
└── common/              # 共通スクリプト
    └── scripts/
```

## 変更管理

- **main**: 安定版ブランチ
- **production**: 本番環境用ブランチ
- **development**: 開発環境用ブランチ

## バージョン

- Kubernetes: v1.31.3
- Calico: v3.28.0
- Kubespray: v2.28.0

## update
2025.10.09 v3.0
