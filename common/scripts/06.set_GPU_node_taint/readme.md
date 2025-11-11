# GPU Environment
この手順はGPUノードを持つProduction環境のみ必要となります

## GPU専用ノード化の設定

### 1. Taint設定
- GPUノードにdedicated=gpu-compute:NoScheduleのTaintを設定すれば、ArgoCDは自動的にGPUノード以外（node01/node02/masterノード）に配置されます。
```bash
# Taint設定後のノード状態
master01-03: Taint: node-role.kubernetes.io/control-plane:NoSchedule（既存）
dlcsv1-2:   Taint: dedicated=gpu-compute:NoSchedule（新規追加）
node01-02:  Taint: なし ← ArgoCDは自然にここに配置される
```

### 2. ラベル付与のデメリット
ラベルを付けると逆に柔軟性が失われます:
- ラベルなし → Kubernetesのスケジューラが最適なノードを自動選択
- ラベルあり → node01/node02に強制的に固定（masterノードが使えなくなる）


