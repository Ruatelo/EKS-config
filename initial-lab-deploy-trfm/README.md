# EKS Attacks Lab - Terraform Deployment

## What This Does
Deploys an Amazon EKS cluster (`eks-attacks-lab`) in `us-east-1` with 2 `t3.small` managed worker nodes, VPC networking, CloudWatch audit logging enabled, and VPC CNI network policy support. Built as a dedicated testing environment for the Kubernetes security YouTube series.

## Prerequisites

### Install Terraform
Installs the official Terraform binary via HashiCorp APT repository.
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list && sudo apt update && sudo apt install -y terraform
```

### Install AWS CLI
Downloads and installs the AWS CLI v2 package for Linux.
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip
```

### Configure AWS Credentials
Configures AWS credentials (requires Access Key ID, Secret Access Key, and default region `us-east-1`).
```bash
aws configure
```

### Install kubectl
Downloads and installs the latest stable `kubectl` release to `/usr/local/bin`.
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl
```

## Deploy the Lab

### Initialize Terraform
Downloads the AWS provider and sets up the local backend.
```bash
terraform init
```

### Preview Changes
Shows what resources will be created without making changes.
```bash
terraform plan
```

### Deploy
Creates all resources (~15 min for EKS cluster and node group).
```bash
terraform apply -auto-approve
```

### Connect to the Cluster
Updates your local kubeconfig and verifies worker nodes are ready.
```bash
aws eks update-kubeconfig --name eks-attacks-lab --region us-east-1
kubectl get nodes
```

## Verify CloudWatch Audit Logs
Checks that CloudWatch log groups are created and capturing control plane audit logs.
```bash
aws logs describe-log-groups --log-group-name-prefix /aws/eks/eks-attacks-lab --region us-east-1
```

## Clean Up / Destroy
Tears down ALL resources to avoid incurring ongoing AWS charges.
```bash
terraform destroy -auto-approve
```

## Resources Created
- **VPC & Subnets**: Dedicated VPC with public and private subnets
- **NAT Gateway**: Outbound internet connectivity for private subnets
- **EKS Cluster**: `eks-attacks-lab` control plane
- **Managed Node Group**: 2x `t3.small` EC2 worker nodes
- **CloudWatch Log Group**: Control plane audit logging
- **VPC CNI Add-on**: Network policy support enabled
- **IAM Roles**: IAM roles and security policies for cluster and node group
