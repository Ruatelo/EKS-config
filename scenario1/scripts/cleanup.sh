#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${1:-eks-attacks-lab}"
REGION="${2:-us-east-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure kubectl targets the right cluster
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

cd "$SCRIPT_DIR/../terraform"
terraform destroy -auto-approve \
  -var="allowed_ip=0.0.0.0/0" \
  -var="cluster_name=$CLUSTER_NAME" \
  -var="region=$REGION"

# Clean up kubectl attack context if present
kubectl config delete-context attack 2>/dev/null || true
kubectl config delete-cluster attack-cluster 2>/dev/null || true
kubectl config unset users.attack-node 2>/dev/null || true
rm -f /tmp/eks-ca.crt

echo "Cleanup complete."
