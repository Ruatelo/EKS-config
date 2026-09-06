# Kubernetes Cluster Auditing with Kubescape

Demonstrates how to use [Kubescape](https://github.com/kubescape/kubescape) to scan a deliberately misconfigured Kubernetes cluster for security risks, compliance violations, and common misconfigurations. The lab deploys a Kind cluster loaded with intentionally insecure workloads so Kubescape has real findings to surface.

## What is Kubescape?

An open-source Kubernetes security platform by [ARMO](https://www.armosec.io/) (CNCF project) that scans clusters, YAML manifests, and Helm charts against multiple compliance frameworks. It covers risk analysis, misconfiguration detection, RBAC analysis, image vulnerability scanning, and CI/CD pipeline integration — all from a single CLI.

## Install

### Standalone (Linux/macOS)
Downloads the latest binary from the Kubescape GitHub releases.
```bash
curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash
```

### Verify Installation
```bash
kubescape version
```

---

## Key Commands

| Command | What It Does |
|---------|-------------|
| `kubescape scan` | Scans the current cluster against the default NSA/CISA framework |
| `kubescape scan framework nsa` | Scans against the NSA/CISA Kubernetes hardening guide |
| `kubescape scan framework mitre` | Scans against the MITRE ATT&CK framework for containers |
| `kubescape scan framework cis-v1.23-t1.0.1` | Scans against the CIS Kubernetes Benchmark |
| `kubescape scan framework AllFrameworks` | Scans against all available frameworks at once |
| `kubescape scan control C-0034` | Scans for a specific control (e.g., C-0034 = automatic mapping of SA) |
| `kubescape scan -n <namespace>` | Scans only a specific namespace |
| `kubescape scan *.yaml` | Scans local YAML manifests before they hit the cluster |
| `kubescape scan --format json -o results.json` | Exports scan results to JSON for programmatic use |
| `kubescape scan --format html -o report.html` | Generates an HTML compliance report |
| `kubescape scan --compliance-threshold 80` | Fails the scan if the compliance score is below 80% |

---

## Use Cases

### 1. Pre-Deployment Manifest Scanning
Scan your YAML files before applying them to catch misconfigurations at authoring time.
```bash
kubescape scan vulnerable-workloads/
```

### 2. Cluster Compliance Audit
Run full compliance audits against industry-standard frameworks.
```bash
kubescape scan framework nsa
kubescape scan framework mitre
kubescape scan framework cis-v1.23-t1.0.1
```

### 3. Targeted Namespace Scanning
Focus scans on specific namespaces to audit workloads in isolation.
```bash
kubescape scan -n insecure-apps
kubescape scan -n exposed-dashboard
```

### 4. Specific Control Checks
Check for individual security controls without running an entire framework.
```bash
# C-0057: Privileged container
kubescape scan control C-0057

# C-0034: Automatic mapping of service account
kubescape scan control C-0034

# C-0044: Container hostPath mount
kubescape scan control C-0044
```

### 5. CI/CD Gate with Compliance Threshold
Fail a pipeline if the cluster or manifests fall below a compliance score.
```bash
kubescape scan --compliance-threshold 70 --format junit -o results.xml
```

## Lab Setup

### Prerequisites
- [Kind](https://kind.sigs.k8s.io/) installed
- kubectl installed
- Kubescape installed (see above)

### Deploy the Lab Cluster

Create the Kind cluster and apply all the intentionally insecure workloads.
```bash
kind create cluster --name kubescape-lab --config cluster-config/kind-config.yaml
kubectl apply -f vulnerable-workloads/
```

### What Gets Deployed

| Component | Namespace | Misconfiguration |
|-----------|-----------|-----------------|
| Kubernetes Dashboard (skip-login) | `exposed-dashboard` | Dashboard deployed with `--enable-skip-login` and `--disable-settings-authorizer` — anyone with network access gets full dashboard without authentication |
| Privileged nginx container | `insecure-apps` | Runs with `privileged: true`, `hostPID: true`, `hostNetwork: true` — full breakout to the host |
| Default SA with cluster-admin | `insecure-apps` | Default service account bound to `cluster-admin` — every pod in the namespace gets full cluster access |
| HostPath root volume mount | `insecure-apps` | Volume mounts the host root filesystem (`/`) into the container at `/host-root` — direct host filesystem access |
| Writable secrets volume mount | `insecure-apps` | Mounts `/etc/kubernetes/pki` (host certs) into the container read-write |
| Overprivileged app | `dev-team` | Container with `allowPrivilegeEscalation: true`, all capabilities added, no read-only root filesystem |
| Unrestricted nginx | `dev-team` | No security context, no resource limits, runs as root — fails every hardening control |


---

## Demo Walkthrough

### 1. Scan the Full Cluster
```bash
kubescape scan
```

### 2. Scan Against Specific Frameworks
```bash
kubescape scan framework nsa
kubescape scan framework mitre
```

### 3. Scan Against All Frameworks
```bash
kubescape scan framework AllFrameworks
```

### 4. Scan a Specific Namespace
```bash
kubescape scan -n insecure-apps
kubescape scan -n exposed-dashboard
```

### 5. Check Specific Controls
```bash
# Privileged containers
kubescape scan control C-0057

# Automatic mapping of service account tokens
kubescape scan control C-0034

# Container hostPath volume mounts
kubescape scan control C-0044

# Cluster admin binding
kubescape scan control C-0035
```

### 6. Export Results
```bash
kubescape scan framework nsa --format json -o nsa-results.json
kubescape scan framework nsa --format html -o nsa-report.html
```

### 7. Pre-Deployment Scan (Shift Left)
Scan the YAMLs before applying them — same findings, no cluster needed.
```bash
kubescape scan vulnerable-workloads/
```

---

## Clean Up

```bash
kind delete cluster --name kubescape-lab
```

## File Structure

```
kubespace-demo/
├── README.md                                       # This file — tool overview, install, CI/CD, demo walkthrough
├── cluster-config/
│   └── kind-config.yaml                            # Kind cluster with 1 control-plane + 1 worker node
└── vulnerable-workloads/
    ├── 00-namespaces.yaml                          # exposed-dashboard, insecure-apps, dev-team namespaces
    ├── 01-dashboard-no-auth.yaml                   # Kubernetes Dashboard with skip-login enabled
    ├── 02-privileged-container.yaml                # Privileged nginx with hostPID/hostNetwork
    ├── 03-default-sa-cluster-admin.yaml            # Default SA bound to cluster-admin in insecure-apps
    ├── 04-hostpath-root-mount.yaml                 # Pod mounting host root (/) as volume
    ├── 05-secrets-volume-mount.yaml                # Pod mounting /etc/kubernetes/pki read-write
    └── 06-overprivileged-workloads.yaml            # Containers with all capabilities, no restrictions
```
