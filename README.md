# EKS-config
EKS config commands for the youtube series

Creating the cluster
```bash
# Create the cluster with 2 worker nodes
eksctl create cluster \
  --name eks-attacks-lab \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.small \
  --nodes 2 \
  --managed
```
Kubectl config
```bash
# Fetch the cluster credentials and update your ~/.kube/config
aws eks update-kubeconfig --name eks-attacks-lab --region us-east-1

# Verify you can see your two t3.small nodes
kubectl get nodes
```

Network policies configuration
```bash
# Create the cluster with 2 worker nodes
# Enable Network Policies on the VPC CNI
aws eks update-addon \
  --cluster-name eks-attacks-lab \
  --addon-name vpc-cni \
  --configuration-values '{"enableNetworkPolicy": "true"}' \
  --resolve-conflicts PRESERVE \
  --region us-east-1
```

Deletign the EKS cluster - clean up
```bash
eksctl delete cluster --name eks-attacks-lab
```
