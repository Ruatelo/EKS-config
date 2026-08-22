# Scenario 1: EKS Privilege Escalation — Pod RCE to Cluster-Admin

Command injection → IMDSv2 credential theft → node token → pod impersonation → cluster-admin.

Based on [Privilege Escalation in EKS — Calif.io](https://blog.calif.io/p/privilege-escalation-in-eks).

## Prerequisites

- EKS cluster deployed via [`initial-lab-deploy-trfm/`](../initial-lab-deploy-trfm/)
- Docker, AWS CLI, kubectl, Terraform installed

## Deploy

```bash
chmod +x scripts/deploy.sh scripts/cleanup.sh
./scripts/deploy.sh "$(curl -s https://checkip.amazonaws.com)/32"
```

Terraform handles everything — ECR repo, Docker build/push, K8s resources, node labeling, EC2 tags, and the IP-whitelisted LoadBalancer.

## What Gets Deployed

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| `health-dashboard` | `default` | Vulnerable Flask app (command injection) via ELB |
| `payment-processor` | `prod` | BusyBox pod with `cluster-admin` SA |

Both pods co-located on the same node. EC2 tags added for attacker recon.

## Why It Works

| EKS Default | Impact |
|-------------|--------|
| IMDS hop limit = 2 | Pods can steal node IAM creds from `169.254.169.254` |
| Node IAM → `system:node` | Stolen IAM creds = K8s node identity |
| NodeRestriction allows `TokenRequest` | Node can mint SA tokens for any pod on itself |

## Exploit Steps

See [CHEATSHEET.md](CHEATSHEET.md).

## Mitigations

1. **IMDS hop limit = 1** — blocks pods from reaching instance metadata
2. **IRSA / EKS Pod Identity** — pods get scoped IAM roles, not the node's
3. **Least-privilege RBAC** — no `cluster-admin` on workload SAs
4. **Network Policies** — block `169.254.169.254/32` egress

## Clean Up

```bash
./scripts/cleanup.sh
```

## File Structure

```
scenario1/
├── vulnerable-app/          # Flask app with command injection + Dockerfile
├── terraform/               # Everything — ECR, K8s resources, node config
│   ├── providers.tf         # AWS + Kubernetes providers
│   ├── variables.tf         # region, cluster_name, allowed_ip
│   ├── main.tf              # ECR repo + Docker build/push
│   ├── kubernetes.tf        # Namespaces, RBAC, Deployment, Service, Pod
│   ├── node.tf              # Node label + EC2 tags
│   └── outputs.tf           # App URL, node info
└── scripts/
    ├── deploy.sh            # Thin wrapper → terraform apply
    └── cleanup.sh           # Thin wrapper → terraform destroy
```
