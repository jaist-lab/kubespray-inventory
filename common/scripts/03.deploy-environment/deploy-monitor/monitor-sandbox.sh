#!/bin/bash
# Masterノードでkubelet確認
#
ssh jaistlab@172.16.100.131 "journalctl -u kubelet -f"

# containerd確認
# ssh jaistlab@172.16.100.131 "journalctl -u containerd -f"

