#!/bin/bash

# Helm でインストール
helm install kepler kepler/kepler \
  --namespace kepler \
  --values values.yaml

# インストール確認
helm list -n kepler
