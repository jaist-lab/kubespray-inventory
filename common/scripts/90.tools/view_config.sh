#!/bin/bash

# ファイルパスとそのサマリーテキストのペアを定義
# 形式: "ファイルパス:::サマリーテキスト"
file_list=(
    "hosts.yml:::1. hosts.yml"
    "group_vars/all/all.yml:::2. group_vars/all/all.yml"
    "group_vars/k8s_cluster/k8s-cluster.yml:::3. group_vars/k8s_cluster/k8s-cluster.yml"
    "group_vars/k8s_cluster/addons.yml:::4. group_vars/k8s_cluster/addons.yml"
    "group_vars/k8s_cluster/k8s-net-calico.yml:::5. group_vars/8s_cluster/k8s-net-calico.yml"
)

# ファイルリストをループ処理
for item in "${file_list[@]}"; do
    # ':::'を区切り文字として、ファイルパスとサマリーテキストを分割
    file_path=$(echo "$item" | cut -d: -f1)
    summary_text=$(echo "$item" | cut -d: -f4)

    # ファイルが存在するか確認
    if [ -f "$file_path" ]; then
        echo "" # 視覚的な区切りのための改行
        echo "<details>"
        echo "<summary>${summary_text}</summary>"
        echo ""
        echo "\`\`\`yaml"
        cat "$file_path"
        echo ""
        echo "\`\`\`"
        echo "</details>"
        echo "" # 視覚的な区切りのための改行
    else
        echo "Warning: File not found - ${file_path}" >&2
    fi
done

echo "" # 最後の区切りのための改行
