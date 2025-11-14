#!/bin/bash

set -e

SCRIPT_DIR=$(cd $(dirname $0); pwd)

echo "==================================="
echo "=== Production クラスター ==="
echo "==================================="
$SCRIPT_DIR/deploy-fluent-bit.sh production

echo ""
echo "==================================="
echo "=== Development クラスター ==="
echo "==================================="
$SCRIPT_DIR/deploy-fluent-bit.sh development

echo ""
echo "==================================="
echo "=== Sandbox クラスター ==="
echo "==================================="
$SCRIPT_DIR/deploy-fluent-bit.sh sandbox

echo ""
echo "==================================="
echo "=== デプロイ完了 ==="
echo "==================================="
