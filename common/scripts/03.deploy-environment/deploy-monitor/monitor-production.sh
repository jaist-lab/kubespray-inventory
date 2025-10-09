#!/bin/bash
# Masterノードでkubelet確認
#
ssh jaist-lab@172.16.100.101 "journalctl -u kubelet -f"

# containerd確認
# ssh jaist-lab@172.16.100.101 "journalctl -u containerd -f"

