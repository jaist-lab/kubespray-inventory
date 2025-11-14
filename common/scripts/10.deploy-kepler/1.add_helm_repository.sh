#!/bin/bash

# Kepler の Helm リポジトリを追加
helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart

# リポジトリを更新
helm repo update

# Chart の確認
helm search repo kepler
