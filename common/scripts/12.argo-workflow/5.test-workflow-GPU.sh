kubectl create -f - << EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: gpu-test-
  namespace: argo
spec:
  serviceAccountName: argo
  entrypoint: gpu-test
  tolerations:
  - key: dedicated
    operator: Equal
    value: gpu-compute
    effect: NoSchedule
  templates:
  - name: gpu-test
    container:
      image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
      command: [python, -c]
      args:
      - |
        import torch
        print("=== GPU Test ===")
        print(f"PyTorch version: {torch.__version__}")
        print(f"CUDA available: {torch.cuda.is_available()}")
        if torch.cuda.is_available():
            print(f"GPU: {torch.cuda.get_device_name(0)}")
            print(f"Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")
            print("=== Test Complete ===")
      resources:
        requests:
          nvidia.com/gpu: "1"
          memory: "1Gi"
          cpu: "500m"
        limits:
          nvidia.com/gpu: "1"
          memory: "2Gi"
          cpu: "1"
EOF

# GPUノード（dlcsv1/dlcsv2）で実行されていることを確認
kubectl get pods -n argo -o wide

# ログでH100 NVL認識を確認
kubectl logs -n argo $(kubectl get pods -n argo -l workflows.argoproj.io/workflow | grep gpu-test | awk '{print $1}' | head -1) -c main

