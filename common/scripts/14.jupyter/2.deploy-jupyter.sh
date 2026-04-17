#!/bin/bash

# Kustomizeで一括デプロイ
kubectl apply -k ml-experiments/

# Pod起動待ち（initContainerのパッケージインストールに時間がかかる）
kubectl wait --for=condition=ready pod -l app=jupyter-gpu -n ml-experiments --timeout=600s