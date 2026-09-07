# EKS IAM Auditing with MKAT (Managed Kubernetes Auditing Toolkit)

Demonstrates how to use [MKAT](https://github.com/DataDog/managed-kubernetes-auditing-toolkit) by Datadog to audit EKS cloud identity configurations — IRSA trust policies, EKS Pod Identity associations, and hardcoded AWS credentials in Kubernetes resources. The lab deploys intentionally misconfigured IAM roles, service accounts, and secrets so MKAT has real findings to surface.

## What is MKAT?

An open-source auditing toolkit by [Datadog Security Labs](https://securitylabs.datadoghq.com/) purpose-built for managed Kubernetes environments. It identifies privilege escalation paths by cross-referencing Kubernetes service accounts and pods with AWS IAM roles, trust policies, and Pod Identity associations — all from a single CLI.

## Install

### Homebrew (Linux/macOS)
```bash
brew tap datadog/mkat https://github.com/datadog/managed-kubernetes-auditing-toolkit
brew install datadog/mkat/managed-kubernetes-auditing-toolkit
```

### Binary Download
Grab the latest release from [GitHub Releases](https://github.com/DataDog/managed-kubernetes-auditing-toolkit/releases).

### Verify Installation
```bash
mkat version
```

---

## Key Commands

| Command | What It Does |
|---------|-------------|
| `mkat eks find-secrets` | Scans ConfigMaps, Secrets, and Pods for hardcoded AWS access keys (AKIA*/ASIA* patterns) |
| `mkat eks find-role-relationships` | Maps which pods can assume which IAM roles via IRSA and Pod Identity — flags overly permissive trust policies |
| `mkat eks test-imds` | Spawns temporary pods to test whether workloads can reach the EC2 Instance Metadata Service (IMDSv1/v2) |

---

## What This Demo Deploys

> [!IMPORTANT]
> **All AWS credentials in this demo are fake.** The access key IDs (`AKIAIOSFODNN7EXAMPLE`, `AKIAI44QH8DHBEXAMPLE`, `AKIAYRJXG5BB6EXAMPLE`) and secret access keys are [AWS's own documentation example values](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html). They will not authenticate to any AWS account and are safe to commit to version control. They exist solely to trigger MKAT's credential detection patterns.

### AWS Resources (Terraform)

| Resource | Name | Misconfiguration |
|----------|------|-----------------|
| IAM Role (IRSA) | `mkat-demo-s3-reader-secure` | ✅ Secure — `StringEquals` with exact SA (`system:serviceaccount:mkat-demo:s3-reader-sa`) |
| IAM Role (IRSA) | `mkat-demo-s3-reader-vulnerable` | ❌ Missing `sub` condition — any pod in the cluster can assume this role |
| IAM Role (IRSA) | `mkat-demo-s3-admin-wildcard` | ❌ Wildcard `sub` via `StringLike` (`system:serviceaccount:mkat-demo:*`) — any SA in namespace gets S3 Full Access |
| IAM Role (Pod Identity) | `mkat-demo-pod-identity-role` | ✅ Secure — associated with specific SA `dynamo-reader-sa` |
| IAM Role (Pod Identity) | `mkat-demo-pod-identity-overprivileged` | ❌ Associated with `default` SA — every pod without an explicit SA gets SecretsManager access |
| S3 Bucket | `mkat-demo-data-*` | Realistic target for the IAM policies |

### Kubernetes Resources (Terraform)

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| `s3-reader-sa` ServiceAccount | `mkat-demo` | IRSA-annotated — secure role with exact SA scoping |
| `s3-vulnerable-sa` ServiceAccount | `mkat-demo` | IRSA-annotated — role missing `sub` condition |
| `s3-wildcard-sa` ServiceAccount | `mkat-demo` | IRSA-annotated — role with wildcard `sub` condition |
| `dynamo-reader-sa` ServiceAccount | `mkat-demo` | Pod Identity — secure, specific SA association |
| `secrets-manager-sa` ServiceAccount | `mkat-demo` | Pod Identity — dedicated SA (but `default` SA in the namespace also has an association) |
| `legacy-app-config` ConfigMap | `mkat-demo` | Hardcoded `AKIAIOSFODNN7EXAMPLE` + secret key in plaintext |
| `backup-cron-config` ConfigMap | `mkat-demo` | Second set of hardcoded AWS credentials with custom key names |
| `database-credentials` Secret | `mkat-demo` | AWS keys embedded inside a database credential Secret |
| 6 Deployments | `mkat-demo` | Pods consuming the above SAs, ConfigMaps, and Secrets |

### IRSA Trust Policy Comparison

```mermaid
graph TD
    A["s3-reader-sa"] -->|"StringEquals (exact SA)"| B["mkat-demo-s3-reader-secure\n✅ S3 Read Only"]
    C["s3-vulnerable-sa"] -->|"No sub condition"| D["mkat-demo-s3-reader-vulnerable\n❌ S3 Read Only\n(any pod in cluster can assume)"]
    E["s3-wildcard-sa"] -->|"StringLike (wildcard *)"| F["mkat-demo-s3-admin-wildcard\n❌ S3 Full Access\n(any SA in namespace can assume)"]
    G["dynamo-reader-sa"] -->|"Pod Identity (specific SA)"| H["mkat-demo-pod-identity-role\n✅ DynamoDB Read Only"]
    I["default SA (implicit)"] -->|"Pod Identity (default SA)"| J["mkat-demo-pod-identity-overprivileged\n❌ SecretsManager Read/Write\n(any pod without explicit SA gets this)"]
    style A fill:#4CAF50,color:#fff
    style B fill:#4CAF50,color:#fff
    style C fill:#f44336,color:#fff
    style D fill:#f44336,color:#fff
    style E fill:#f44336,color:#fff
    style F fill:#f44336,color:#fff
    style G fill:#4CAF50,color:#fff
    style H fill:#4CAF50,color:#fff
    style I fill:#f44336,color:#fff
    style J fill:#f44336,color:#fff
```

---

## Prerequisites

- EKS cluster deployed via [`initial-lab-deploy-trfm/`](../initial-lab-deploy-trfm/) (OIDC provider must be enabled)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3.0
- AWS CLI configured with permissions for IAM, EKS, and S3
- kubectl configured to the target cluster
- MKAT installed (see above)

---

## Deploy the Lab

### 1. Update kubeconfig
```bash
aws eks update-kubeconfig --name eks-attacks-lab --region us-east-1
```

### 2. Deploy Everything (Terraform)
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

> [!NOTE]
> Everything is managed 100% via Terraform in a single `terraform apply` command:
> - **AWS Resources**: IAM roles (IRSA & Pod Identity), OIDC provider, EKS Pod Identity Agent add-on, associations, and S3 bucket.
> - **Kubernetes Resources**: Namespace (`mkat-demo`), 5 ServiceAccounts (with live IAM role ARNs automatically injected into annotations), ConfigMaps & Secret (with test credentials), and all 6 Deployments.
> No extra bash scripts or `kubectl apply` commands are required!

### 3. Verify Deployments
```bash
kubectl get all -n mkat-demo
kubectl get sa -n mkat-demo
kubectl get cm,secret -n mkat-demo
```

---

## Demo Walkthrough

### 1. Find Hardcoded AWS Credentials
```bash
mkat eks find-secrets
```

**Expected findings:**
- `legacy-app-config` ConfigMap — `AKIAIOSFODNN7EXAMPLE` + paired secret key
- `backup-cron-config` ConfigMap — `AKIAI44QH8DHBEXAMPLE` + paired secret key
- `database-credentials` Secret — `AKIAYRJXG5BB6EXAMPLE` + paired secret key

### 2. Audit IAM Role Relationships (IRSA + Pod Identity)
```bash
mkat eks find-role-relationships
```

**Expected findings:**
- `mkat-demo-s3-reader-vulnerable` — assumable by **any service account in the cluster** (missing `sub` condition)
- `mkat-demo-s3-admin-wildcard` — assumable by **any service account in the `mkat-demo` namespace** (wildcard `sub`)
- `mkat-demo-pod-identity-overprivileged` — Pod Identity association on the **`default` service account** (any pod without an explicit SA gets SecretsManager access)
- `mkat-demo-s3-reader-secure` — properly scoped (✅ no finding)
- `mkat-demo-pod-identity-role` — properly scoped (✅ no finding)

To see full role ARNs and output a graph:
```bash
mkat eks find-role-relationships --show-full-role-arns
mkat eks find-role-relationships --output-format dot --output-file mkat-roles.dot
```

### 3. Test IMDS Reachability
```bash
mkat eks test-imds
```

**Expected findings** (based on the base cluster's `http_put_response_hop_limit = 2`):
- IMDSv2 is reachable from pods (hop limit allows container-to-IMDS traffic)

---

## Clean Up

A single `terraform destroy` removes all AWS resources and all Kubernetes workloads cleanly:

```bash
cd terraform/
terraform destroy
```

---

## References

- [MKAT GitHub Repository](https://github.com/DataDog/managed-kubernetes-auditing-toolkit)
- [Attacking and Securing Cloud Identities in Managed Kubernetes: Amazon EKS](https://securitylabs.datadoghq.com/articles/amazon-eks-attacking-securing-cloud-identities/) — Datadog Security Labs
- [EKS Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

## File Structure

```
mkat-demo/
├── README.md                                    # This file — tool overview, install, demo walkthrough
└── terraform/
    ├── providers.tf                             # AWS, Kubernetes, TLS, Random providers & EKS data sources
    ├── variables.tf                             # region and cluster_name variables
    ├── irsa.tf                                  # OIDC provider, Pod Identity Agent addon, S3 bucket, 3 IRSA roles (secure + 2 vulnerable)
    ├── pod-identity.tf                          # 2 Pod Identity roles + associations (secure + default SA overprivileged)
    ├── kubernetes.tf                            # 100% Terraform: namespace, 5 SAs with dynamic ARNs, ConfigMaps, Secret, 6 Deployments
    └── outputs.tf                               # Role ARNs, bucket name, kubeconfig command
```
