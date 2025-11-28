#!/bin/bash

echo "### 1. Helmリポジトリの設定"

# NVIDIAのHelmリポジトリを追加
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia

# リポジトリの更新
helm repo update

# 利用可能なGPU Operatorバージョンの確認
helm search repo nvidia/gpu-operator --versions | head -10

echo "### 2. ネームスペース作成"
# gpu-operator専用ネームスペースの作成
kubectl create namespace gpu-operator

# ネームスペース確認
kubectl get namespaces | grep gpu-operator
