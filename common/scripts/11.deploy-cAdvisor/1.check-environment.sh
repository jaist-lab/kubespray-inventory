#!/bin/bash

# 現在のノード状況確認
kubectl get nodes -o wide

# GPU専用化確認
kubectl describe nodes dlcsv1 dlcsv2 | grep Taints

# 監視システム確認
kubectl get pods -n monitoring | grep prometheus
