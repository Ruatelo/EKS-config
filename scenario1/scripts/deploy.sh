#!/usr/bin/env bash
set -euo pipefail

ALLOWED_IP="${1:?Usage: ./deploy.sh <YOUR_PUBLIC_IP/32>  e.g., ./deploy.sh 203.0.113.42/32}"
CLUSTER_NAME="${2:-eks-attacks-lab}"
REGION="${3:-us-east-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure kubectl is configured for the cluster
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

cd "$SCRIPT_DIR/../terraform"
terraform init -input=false
terraform apply -auto-approve \
  -var="allowed_ip=$ALLOWED_IP" \
  -var="cluster_name=$CLUSTER_NAME" \
  -var="region=$REGION"

echo ""
echo "============================================"
echo "  Vulnerable App: $(terraform output -raw app_url)"
echo "  Allowed IP:     $ALLOWED_IP"
echo "============================================"
