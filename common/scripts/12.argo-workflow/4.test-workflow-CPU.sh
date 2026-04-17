kubectl create -f - << EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: cpu-test-
  namespace: argo
spec:
  entrypoint: hello
  templates:
  - name: hello
    container:
      image: alpine:latest
      command: [echo, "CPU test successful"]
      resources:
        requests:
          memory: "64Mi"
          cpu: "100m"
EOF

# Succeeded になることを確認
kubectl get workflows -n argo
