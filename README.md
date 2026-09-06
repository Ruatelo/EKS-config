# EKS Security & Attack Scenarios Lab

Hands-on Kubernetes security testing environment and reference architecture for reproducing, detecting, and mitigating real-world Amazon EKS privilege escalation vectors and attack paths.

---

## Lab Architecture

The base infrastructure deploys a dedicated Amazon EKS cluster configured with:
- Multi-AZ VPC networking with public and private subnets
- EKS Control Plane audit logging streamed to AWS CloudWatch
- AWS CloudTrail integration for IAM management event auditing
- AWS VPC CNI with native NetworkPolicy enforcement enabled

To deploy the base cluster, see [`initial-lab-deploy-trfm/`](initial-lab-deploy-trfm/).

---

## Scenarios

### [Scenario 1: Pod RCE to Cluster-Admin via Node Token Impersonation](scenario1/)
Demonstrates how an application-level Remote Code Execution (RCE) vulnerability allows an attacker to query the EC2 Instance Metadata Service (IMDSv2), obtain the worker node's IAM role, authenticate to Kubernetes as `system:node`, and abuse `NodeRestriction` token requests to impersonate a privileged ServiceAccount in a production namespace.

* **Exploit Reference:** [`scenario1/CHEATSHEET.md`](scenario1/CHEATSHEET.md)
* **CloudWatch Detection Queries:** [`scenario1/DETECTIONS.md`](scenario1/DETECTIONS.md)
* **Incident Response Runbook:** [`scenario1/IncidentResponse.md`](scenario1/IncidentResponse.md)

### [RBAC Enumeration with rbac-tool (Rapid7)](rbac-tool-demo/)
Demonstrates how to enumerate, visualize, and audit Kubernetes RBAC configurations using Rapid7's `rbac-tool`. Deploys a Kind cluster with multiple namespaces, service accounts at varying privilege levels, and a least-privilege service account for running the tool itself.

* **Tool Overview & Demo Walkthrough:** [`rbac-tool-demo/README.md`](rbac-tool-demo/README.md)
* **Cluster Configuration:** [`rbac-tool-demo/cluster-config/`](rbac-tool-demo/cluster-config/)

### [Kubernetes Cluster Auditing with Kubescape](kubescape-demo/)
Demonstrates how to use Kubescape to scan a deliberately misconfigured Kind cluster for security risks, compliance violations, and common misconfigurations. Deploys an unauthenticated dashboard, privileged containers, overprivileged service accounts, and insecure volume mounts for Kubescape to detect.

* **Tool Overview & Demo Walkthrough:** [`kubescape-demo/README.md`](kubescape-demo/README.md)
* **Cluster Configuration:** [`kubescape-demo/cluster-config/`](kubescape-demo/cluster-config/)
* **Vulnerable Workloads:** [`kubescape-demo/vulnerable-workloads/`](kubescape-demo/vulnerable-workloads/)

---

*Additional attack scenarios will be added sequentially.*
