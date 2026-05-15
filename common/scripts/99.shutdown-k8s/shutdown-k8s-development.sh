#!/bin/bash
# Vessel shutdown script for production Kubernetes cluster
# This script will drain and delete all nodes in the production Kubernetes cluster  

# Set the K8S_CLUSTER environment variable to specify the target cluster
export K8S_CLUSTER="development-cluster"
export KUBECONFIG=~/.kube/config-development

# ワーカーノードのDrain 新規Podのスケジュールを停止し、既存Podを安全に退避する。
kubectl drain dev-node01 --ignore-daemonsets --delete-emptydir-data --force
kubectl drain dev-node02 --ignore-daemonsets --delete-emptydir-data --force

#ワーカーノードのサービス停止
ssh jaistlab@172.16.100.124 "sudo systemctl stop kubelet && sudo systemctl stop containerd"
ssh jaistlab@172.16.100.125 "sudo systemctl stop kubelet && sudo systemctl stop containerd"

# コントロールプレーンの停止
ssh jaistlab@172.16.100.123 "sudo systemctl stop kubelet && sudo systemctl stop containerd"
ssh jaistlab@172.16.100.122 "sudo systemctl stop kubelet && sudo systemctl stop containerd"
ssh jaistlab@172.16.100.121 "sudo systemctl stop kubelet && sudo systemctl stop containerd"

#etcdの停止
ssh jaistlab@172.16.100.123 "sudo systemctl stop etcd"
ssh jaistlab@172.16.100.122 "sudo systemctl stop etcd"
ssh jaistlab@172.16.100.121 "sudo systemctl stop etcd"

# master01で確認
ssh jaistlab@172.16.100.121 "sudo systemctl is-active etcd kubelet containerd"
# 3行とも inactive であること

# ワーカーノードで確認（例: node01）
ssh jaistlab@172.16.100.124 "sudo systemctl is-active kubelet containerd"
# 2行とも inactive であること