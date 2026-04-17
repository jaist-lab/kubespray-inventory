#!/bin/bash
# 各GPUノードでディレクトリ作成
for node in dlcsv1 dlcsv2; do
    ssh $node "sudo mkdir -p /mnt/jupyter-workspace /mnt/datasets && sudo chmod 755 /mnt/jupyter-workspace /mnt/datasets"
    echo "Directories created on $node"
done