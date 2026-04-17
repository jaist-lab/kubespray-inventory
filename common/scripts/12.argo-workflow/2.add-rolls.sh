#!/bin/bash

# 完全な権限設定（RoleとClusterRoleの両方）
kubectl apply -f - << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: argo
  name: workflow-executor-enhanced
rules:
- apiGroups: ["argoproj.io"]
  resources: ["workflowtaskresults"]
  verbs: ["create", "patch", "get", "list", "watch", "update", "delete"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: workflow-executor-enhanced-binding
  namespace: argo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: workflow-executor-enhanced
subjects:
- kind: ServiceAccount
  name: default
  namespace: argo
- kind: ServiceAccount
  name: argo
  namespace: argo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: workflow-task-results-access
rules:
- apiGroups: ["argoproj.io"]
  resources: ["workflowtaskresults"]
  verbs: ["create", "patch", "get", "list", "watch", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: workflow-task-results-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: workflow-task-results-access
subjects:
- kind: ServiceAccount
  name: argo
  namespace: argo
- kind: ServiceAccount
  name: default
  namespace: argo
EOF

# 権限が正しく設定されているか確認
kubectl auth can-i create workflowtaskresults --as=system:serviceaccount:argo:argo -n argo
kubectl auth can-i create workflowtaskresults --as=system:serviceaccount:argo:default -n argo

# 両方とも "yes" が返ることを確認
