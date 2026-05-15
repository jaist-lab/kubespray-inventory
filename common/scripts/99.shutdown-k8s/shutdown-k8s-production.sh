#!/bin/bash
# Vessel shutdown script for production Kubernetes cluster
# This script will drain and delete all nodes in the production Kubernetes cluster  

# Set the K8S_CLUSTER environment variable to specify the target cluster
export K8S_CLUSTER="production-cluster"
export KUBECONFIG=~/.kube/config-production

# ワーカーノードのDrain 新規Podのスケジュールを停止し、既存Podを安全に退避する。
kubectl drain node01 --ignore-daemonsets --delete-emptydir-data --force
kubectl drain node02 --ignore-daemonsets --delete-emptydir-data --force
kubectl drain dlcsv1 --ignore-daemonsets --delete-emptydir-data --force
# kubectl drain dlcsv2 --ignore-daemonsets --delete-emptydir-data --force

#ワーカーノードのサービス停止
ssh jaistlab@172.16.100.104 "sudo systemctl stop kubelet && sudo systemctl stop containerd"
ssh jaistlab@172.16.100.105 "sudo systemctl stop kubelet && sudo systemctl stop containerd"
ssh jaistlab@172.16.100.31  "sudo systemctl stop kubelet && sudo systemctl stop containerd"
#ssh jaistlab@172.16.100.32  "sudo systemctl stop kubelet && sudo systemctl stop containerd"

# コントロールプレーンの停止
ssh jaistlab@172.16.100.103 "sudo systemctl stop kubelet && sudo systemctl stop containerd"
ssh jaistlab@172.16.100.102 "sudo systemctl stop kubelet && sudo systemctl stop containerd"
ssh jaistlab@172.16.100.101 "sudo systemctl stop kubelet && sudo systemctl stop containerd"

#etcdの停止
ssh jaistlab@172.16.100.103 "sudo systemctl stop etcd"
ssh jaistlab@172.16.100.102 "sudo systemctl stop etcd"
ssh jaistlab@172.16.100.101 "sudo systemctl stop etcd"

# master01で確認
ssh jaistlab@172.16.100.101 "sudo systemctl is-active etcd kubelet containerd"
# 3行とも inactive であること

# ワーカーノードで確認（例: node01）
ssh jaistlab@172.16.100.104 "sudo systemctl is-active kubelet containerd"
# 2行とも inactive であること