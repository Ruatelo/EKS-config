# Threat Detection & CloudWatch Insights Guide for Scenario 1

This guide covers how to detect every stage of the **RCE -> IMDSv2 -> Node IAM -> Pod Impersonation -> Cluster-Admin** attack chain, including required log sources, AWS GuardDuty findings, and raw CloudWatch Logs Insights queries.

---

## 1. Attack Visibility Matrix

| Killchain Phase | Attack Action | Log Source / Security Tool | Log Group / Service |
| :--- | :--- | :--- | :--- |
| **Phase 1: App RCE** | Command Injection (`/check?host=;id`) | Container Stdout / Access Logs | `/aws/containerinsights/eks-attacks-lab/application` or WAF |
| **Phase 2: IMDSv2 Theft** | Pod querying `169.254.169.254` | Amazon GuardDuty EKS Runtime Monitoring | GuardDuty Findings (`UnauthorizedAccess:EC2/MetadataDNSRebind`, etc.) |
| **Phase 3: AWS Recon** | `aws sts get-caller-identity`, `aws ec2 describe-tags` with node creds | AWS CloudTrail (Management Events) | `/aws/cloudtrail/eks-attacks-lab` |
| **Phase 4: Node Recon** | `system:node` running `kubectl get pods -A`, `kubectl auth whoami` | EKS Control Plane Audit Logs | `/aws/eks/eks-attacks-lab/cluster` |
| **Phase 5: Token Escalation** | `kubectl create token prod-admin-sa` bound to pod | EKS Control Plane Audit Logs | `/aws/eks/eks-attacks-lab/cluster` |
| **Phase 6: Cluster Takeover** | `kubectl auth can-i '*' '*'`, dumping secrets | EKS Control Plane Audit Logs | `/aws/eks/eks-attacks-lab/cluster` |

---

## 2. Amazon GuardDuty & Runtime Monitoring

### GuardDuty EKS Protection:
* **EKS Audit Logs Analysis**: Detects anomalous behavior in Kubernetes audit logs (e.g., suspicious API calls, unusual user agents, unmapped users).
* **EKS Runtime Monitoring (eBPF)**: Operates at the host kernel level using an eBPF security agent to monitor file, process, and network activity inside pods.

### Key GuardDuty Findings for this Scenario:
1. **`PrivilegeEscalation:Kubernetes/PrivilegedContainer`**
   * Triggered when unexpected privilege escalation patterns occur inside containers.
2. **`CredentialAccess:Kubernetes/SuccessfulAnonymousAuth`** or **`UnauthorizedAccess:EC2/MetadataDNSRebind`**
   * Flags suspicious requests to the metadata service from non-standard container processes.
3. **`Stealth:IAMUser/AnomalousBehavior`** / **`UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS`**
   * Triggered when EC2 instance profile credentials (stolen from IMDS) are used outside of AWS (e.g. from the attacker's laptop).

---

## 3. Practical Incident Response Workflow (How to Actually Investigate)

Kubernetes audit logs can be overwhelming. Rather than memorizing every API endpoint, real incident response uses a simple 2-step approach:

1. **Spot the Anomaly**: Look for any `system:node` identity using `kubectl` (or any non-kubelet User-Agent) or requesting a token.
2. **Pivot on Source IP / User-Agent**: Once you identify the attacker's IP address, run a single query filtering by that IP to see their **entire chronological attack story**.

---

## 4. CloudWatch Logs Insights Detection Queries

---

### Query 0: The "Trace Attacker Session" Query (Once you have an IP)

* **Log Group:** `/aws/eks/eks-attacks-lab/cluster`
* **Why it matters:** Shows the complete attack timeline across every role switch, namespace, and command.

```sql
fields @timestamp, user.username, verb, objectRef.resource, objectRef.subresource, objectRef.namespace, objectRef.name, requestURI, responseStatus.code
| filter sourceIPs.0 = "YOUR_ATTACKER_IP"   # e.g., "68.147.119.14"
| sort @timestamp asc
| limit 100
```

---

### Query 1: The "Smoking Gun" — Node Impersonating & Requesting SA Tokens (`TokenRequest`)

* **Log Group:** `/aws/eks/eks-attacks-lab/cluster`
* **Why it matters:** A worker node should never interactively request tokens for service accounts in foreign namespaces.
* **Normal vs Abnormal:** Normal kubelet traffic uses `kubelet` user-agent during pod startup. Abnormal requests originate from interactive tools like `kubectl` requesting tokens for high-privilege SAs.

```sql
fields @timestamp, user.username, sourceIPs.0, userAgent, verb, objectRef.resource, objectRef.subresource, objectRef.namespace, objectRef.name, responseStatus.code
| filter objectRef.subresource = "token" or objectRef.resource = "serviceaccounts"
| filter verb = "create"
| filter user.username like /^system:node:/
| sort @timestamp desc
| limit 50
```

> **To filter out normal background kubelet noise and isolate the attacker:**
> ```sql
> fields @timestamp, user.username, sourceIPs.0, userAgent, verb, objectRef.resource, objectRef.subresource, objectRef.namespace, objectRef.name, responseStatus.code
> | filter objectRef.subresource = "token" or objectRef.resource = "serviceaccounts"
> | filter verb = "create"
> | filter user.username like /^system:node:/
> | filter userAgent not like /^kubelet/
> | sort @timestamp desc
> | limit 50
> ```

> **Indicators of Compromise (IoC):**
> - `user.username`: `system:node:ip-10-0-3-101.ec2.internal`
> - `objectRef.namespace`: `prod`
> - `objectRef.name`: `prod-admin-sa`
> - `userAgent`: `kubectl/...`

---

### Query 2: Node Account Performing Abnormal Recon (`get pods -A`, `whoami`)

* **Log Group:** `/aws/eks/eks-attacks-lab/cluster`
* **Why it matters:** Normal kubelets only query pods on their own node using specific internal filters. Listing all namespaces or checking permissions indicates an attacker with stolen node creds.

```sql
fields @timestamp, user.username, sourceIPs.0, userAgent, verb, objectRef.resource, objectRef.namespace, objectRef.name, responseStatus.code
| filter user.username like /^system:node:/
| filter objectRef.resource in ["pods", "namespaces", "services", "selfsubjectreviews"]
| filter verb in ["get", "list"]
| filter userAgent not like /^kubelet/
| sort @timestamp desc
| limit 100
```

> **Indicators of Compromise (IoC):**
> - `userAgent`: `kubectl/...` or `aws-cli/...` instead of `kubelet/...`
> - `sourceIPs`: External public IP address.

---

### Query 3: Cluster-Admin Abuse by the Pivoted Service Account

* **Log Group:** `/aws/eks/eks-attacks-lab/cluster`
* **Why it matters:** Detects unauthorized auditing or privilege verification using the compromised `prod-admin-sa`.

```sql
fields @timestamp, user.username, sourceIPs.0, userAgent, verb, objectRef.resource, objectRef.namespace, responseStatus.code, requestURI
| filter user.username = "system:serviceaccount:prod:prod-admin-sa"
| sort @timestamp desc
| limit 50
```

> **To specifically catch privilege audits (`can-i --list`, `whoami`) and sensitive resource queries:**
> ```sql
> fields @timestamp, user.username, sourceIPs.0, userAgent, verb, objectRef.resource, objectRef.namespace, responseStatus.code, requestURI
> | filter user.username = "system:serviceaccount:prod:prod-admin-sa"
> | filter objectRef.resource in ["selfsubjectrulesreviews", "selfsubjectreviews", "selfsubjectaccessreviews", "secrets", "clusterrolebindings", "nodes"]
> | sort @timestamp desc
> | limit 50
> ```

---

### Query 4: CloudTrail Stolen Node Credentials Used Externally

* **Log Group:** `/aws/cloudtrail/eks-attacks-lab`
* **Why it matters:** Node IAM role credentials should only originate from EC2 instances within the VPC, not from public residential/VPN IPs.

```sql
fields @timestamp, eventName, eventSource, userIdentity.arn, sourceIPAddress, userAgent
| filter userIdentity.arn like /eks-attacks-lab-node-role/
| filter eventName in ["GetCallerIdentity", "DescribeTags", "DescribeInstances"]
| filter sourceIPAddress not like /^10\./ and sourceIPAddress not like /^172\./ and sourceIPAddress not like /^192\.168\./
| sort @timestamp desc
| limit 50
```

> **Indicators of Compromise (IoC):**
> - `sourceIPAddress`: Non-VPC IP address.
> - `eventName`: `DescribeTags` or `GetCallerIdentity`.
