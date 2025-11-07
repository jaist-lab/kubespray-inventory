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

sample_dir="/home/jaist-lab/kubernetes/kubespray/inventory/sample"

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
        echo "\`\`\`diff"

        cat "$sample_dir/$file_path" | grep -v "^#" |grep -v ^$ > /tmp/left.txt
	cat "./$file_path"           | grep -v "^#" |grep -v ^$ > /tmp/right.txt
        #diff "$sample_dir/$file_path" "./$file_path"
        diff /tmp/left.txt /tmp/right.txt

        echo ""
        echo "\`\`\`"
        echo "</details>"
        echo "" # 視覚的な区切りのための改行
    else
        echo "Warning: File not found - ${file_path}" >&2
    fi
done

echo "" # 最後の区切りのための改行
