#!/bin/bash

# Production クラスタを登録
export KUBECONFIG=/home/jaist-lab/.kube/config-production
argocd cluster add $(kubectl config current-context) \
  --name production \
  --kubeconfig /home/jaist-lab/.kube/config-production
echo "Production"登録完了

# Development クラスタを登録
export KUBECONFIG=/home/jaist-lab/.kube/config-development
argocd cluster add $(kubectl config current-context) \
  --name development \
  --kubeconfig /home/jaist-lab/.kube/config-development
echo "Development"登録完了


# Sandbox クラスタを登録
export KUBECONFIG=/home/jaist-lab/.kube/config-sandbox
argocd cluster add $(kubectl config current-context) \
  --name sandbox \
  --kubeconfig /home/jaist-lab/.kube/config-sandbox
echo "Sandbox"登録完了

argocd cluster list

