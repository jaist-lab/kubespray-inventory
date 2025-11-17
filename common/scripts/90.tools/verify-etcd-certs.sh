#!/bin/bash
# etcd証明書設定の検証スクリプト
   
   ENVIRONMENT=$1
   if [ -z "$ENVIRONMENT" ]; then
       echo "Usage: $0 {production|development|sandbox}"
       exit 1
   fi
   
   case $ENVIRONMENT in
       production)
           MASTERS="master01 master02 master03"
           PREFIX="master"
           ;;
       development)
           MASTERS="dev-master01 dev-master02 dev-master03"
           PREFIX="dev-master"
           ;;
       sandbox)
           MASTERS="sandbox-master01 sandbox-master02 sandbox-master03"
           PREFIX="sandbox-master"
           ;;
   esac
   
   echo "===== Verifying etcd certificate configuration for $ENVIRONMENT ====="
   ERRORS=0
   
   for master in $MASTERS; do
       CERT=$(ssh $master "sudo grep 'etcd-certfile' /etc/kubernetes/manifests/kube-apiserver.yaml" | awk -F'=' '{print $2}')
       EXPECTED="/etc/ssl/etcd/ssl/node-${master}.pem"
       
       if [ "$CERT" = "$EXPECTED" ]; then
           echo "✓ $master: OK ($CERT)"
       else
           echo "✗ $master: MISMATCH - Expected: $EXPECTED, Got: $CERT"
           ERRORS=$((ERRORS + 1))
       fi
   done
   
   echo ""
   if [ $ERRORS -eq 0 ]; then
       echo "✓ All certificates are correctly configured"
       exit 0
   else
       echo "✗ Found $ERRORS certificate configuration error(s)"
       exit 1
   fi
