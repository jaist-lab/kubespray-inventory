#!/bin/bash
# 全ノードでSWAP確認（すべて無効であること）、containerd確認、FW確認
# Production環境確認
echo "*** Production ***"
for host in master01 master02 master03 node01 node02 ; do
    echo "=== $host ==="
    echo -n "   swap     :"
    ssh jaist-lab@$host "free -h | grep -i swap"
    echo -n "   containerd    :"
    ssh jaist-lab@$host "sudo systemctl status containerd | grep Active"
    echo -n "   ufw       :"
    ssh jaist-lab@$host "sudo ufw status | head -5"
    echo " "
done
echo " "

echo "*** Development ***"
for host in dev-master01 dev-master02 dev-master03 dev-node01 dev-node02 ; do
    echo "=== $host ==="
    echo -n "   swap     :"
    ssh jaist-lab@$host "free -h | grep -i swap"
    echo -n "   containerd    :"
    ssh jaist-lab@$host "sudo systemctl status containerd | grep Active"
    echo -n "   ufw       :"
    ssh jaist-lab@$host "sudo ufw status | head -5"
    echo " "
done
echo " "

echo "*** Sandbox ***"
for host in sandbox-master01 sandbox-master02 sandbox-master03 sandbox-node01 node02 ; do
    echo "=== $host ==="
    echo -n "   swap     :"
    ssh jaist-lab@$host "free -h | grep -i swap"
    echo -n "   containerd    :"
    ssh jaist-lab@$host "sudo systemctl status containerd | grep Active"
    echo -n "   ufw       :"
    ssh jaist-lab@$host "sudo ufw status | head -5"
    echo " "
done
echo " "
