# Incident Response Runbook: EKS Pod RCE to Cluster-Admin Compromise

This runbook provides the step-by-step containment, eradication, and post-incident hardening actions when an attacker compromises a pod, accesses IMDS, and escalates to `cluster-admin` via node token impersonation.

---

## Immediate Emergency Response (Containment)

Execute these steps in order to immediately cut off the attacker's active access.

```
┌─────────────────────────┐     ┌─────────────────────────┐     ┌─────────────────────────┐
│ 1. Cut Ingress & Scale  │---->│ 2. Revoke SA Token &    │---->│ 3. Revoke Stolen EC2    │
│    Vulnerable Pod to 0  │     │    Delete ClusterBinding│     │    Node IAM Credentials │
└─────────────────────────┘     └─────────────────────────┘     └─────────────────────────┘
```

---

### Step 1: Contain the Entry Point (Stop Pod Respawn & External Ingress)

If you simply run `kubectl delete pod`, the Deployment/ReplicaSet will immediately recreate a fresh vulnerable pod. You must scale the Deployment to `0` and cut external LoadBalancer access.

```bash
# 1. Scale deployment to 0 replicas so it cannot respawn
kubectl scale deployment health-dashboard --replicas=0 -n default

# 2. Block the attacker's IP or delete the LoadBalancer Service immediately
kubectl delete svc health-dashboard -n default
```

> **Why this works:** Scaling to 0 immediately terminates the running pod and prevents the Kubernetes controller-manager from spawning a replacement container.

---

### Step 2: Invalidate the Compromised `cluster-admin` ServiceAccount Token

Kubernetes `TokenRequest` tokens (projected tokens) are cryptographic JWTs validated statelessly by the API server. However, because they are bound to the `Pod` and the `ServiceAccount` object:

#### Action A: Delete the Target Pod & Overprivileged ClusterRoleBinding
```bash
# 1. Delete the ClusterRoleBinding immediately (removes cluster-admin privileges from the token in-flight!)
kubectl delete clusterrolebinding prod-admin-binding

# 2. Delete the pod the token was bound to (invalidates the TokenRequest bound-object check)
kubectl delete pod payment-processor -n prod --grace-period=0 --force
```

#### Action B: Invalidate ALL Existing Tokens by Deleting the ServiceAccount
```bash
# Deleting the ServiceAccount changes its UID — ANY existing JWT token minted for this SA is instantly invalid!
kubectl delete sa prod-admin-sa -n prod
```

> **How Token Invalidation Works in Kubernetes:**
> - When `kube-apiserver` validates a `TokenRequest` JWT token, it verifies that the `ServiceAccount` UID and the bound `Pod` UID still exist in etcd.
> - **Deleting the `ClusterRoleBinding`** instantly neutralizes any active permissions in the token.
> - **Deleting the `ServiceAccount`** causes all future API calls with that token to return `401 Unauthorized: service account not found`.

---

### Step 3: Revoke Stolen EC2 Node IAM Session Credentials (AWS Level)

The attacker also possesses temporary AWS IAM credentials for the EC2 worker node stolen via IMDSv2.

#### Action A: Attach an Explicit Deny Inline Policy to the Node Role
Attach an inline revocation policy to the Node IAM Role (`eks-attacks-lab-node-role`) with a time condition to revoke all existing sessions:

```bash
aws iam put-role-policy \
  --role-name eks-attacks-lab-node-role \
  --policy-name EmergencyRevokeActiveSessions \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Deny",
        "Action": "*",
        "Resource": "*",
        "Condition": {
          "DateLessThan": {
            "aws:TokenIssueTime": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
          }
        }
      }
    ]
  }'
```

#### Action B: Isolate and Terminate the Compromised EC2 Node
```bash
# 1. Cordon and drain the node to evict any legitimate workloads safely
NODE_NAME="ip-10-0-3-101.ec2.internal"
kubectl cordon "$NODE_NAME"
kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --force

# 2. Terminate the EC2 instance (Auto Scaling will launch a clean node)
INSTANCE_ID="i-0cd562eb602a82321"
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region us-east-1
```

---

## Step 4: Eradication & Backdoor Hunting

Once containment is complete, verify if the attacker planted persistent backdoors before access was cut:

### 1. Check `aws-auth` ConfigMap or EKS Access Entries (AWS Auth Backdoors)
Attackers commonly backdoor `aws-auth` to map their external IAM user to `system:masters`.
```bash
kubectl get configmap aws-auth -n kube-system -o yaml
```
*Look for unknown `rolearn` or `userarn` mappings.*

### 2. Audit All `ClusterRoleBindings` & `ClusterRoles`
```bash
kubectl get clusterrolebindings -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.roleRef.name}{"\t"}{.subjects[*].name}{"\n"}{end}' | grep cluster-admin
```
*Verify no unauthorized ServiceAccounts or Users were granted `cluster-admin`.*

### 3. Check for Rogue CronJobs, DaemonSets, or Webhooks
```bash
kubectl get cronjobs,daemonsets,mutatingwebhookconfigurations,validatingwebhookconfigurations -A
```

---

## Step 5: Post-Incident Remediation & Hardening (Copy-Pasteable Fixes)

### 1. Enforce IMDSv2 Hop Limit = 1 on Nodes (Blocks Pod IMDS Access)
```bash
# Get all running EC2 worker nodes
NODE_INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:kubernetes.io/cluster/eks-attacks-lab,Values=owned" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text --region us-east-1)

# Apply hop limit 1 to all nodes immediately
for ID in $NODE_INSTANCE_IDS; do
  echo "Setting hop limit = 1 on instance $ID..."
  aws ec2 modify-instance-metadata-options \
    --instance-id "$ID" \
    --http-put-response-hop-limit 1 \
    --http-tokens required \
    --http-endpoint enabled \
    --region us-east-1
done
```

---

### 2. Apply NetworkPolicy Blocking IMDS Egress Cluster-Wide
Requires VPC CNI with NetworkPolicy enabled (`aws_eks_addon.vpc_cni`).
```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-imds-access
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 169.254.169.254/32
EOF
```

---

### 3. Enforce Least-Privilege RBAC (Fine-Grained Role)
Never grant `cluster-admin`. Replace it with a scoped namespace role:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: payment-processor-role
  namespace: prod
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: payment-processor-binding
  namespace: prod
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: payment-processor-role
subjects:
- kind: ServiceAccount
  name: prod-admin-sa
  namespace: prod
EOF
```

---

### 4. Enable GuardDuty EKS Runtime Monitoring
```bash
# 1. Enable GuardDuty Detector if not active
DETECTOR_ID=$(aws guardduty list-detectors --query "DetectorIds[0]" --output text --region us-east-1)
if [ "$DETECTOR_ID" == "None" ] || [ -z "$DETECTOR_ID" ]; then
  DETECTOR_ID=$(aws guardduty create-detector --enable --region us-east-1 --query "DetectorId" --output text)
fi

# 2. Enable EKS Runtime Monitoring & Audit Logs feature
aws guardduty update-detector \
  --detector-id "$DETECTOR_ID" \
  --features '[{"Name": "EKS_RUNTIME_MONITORING", "Status": "ENABLED", "AdditionalConfiguration": [{"Name": "EKS_ADDON_MANAGEMENT", "Status": "ENABLED"}]}, {"Name": "EKS_AUDIT_LOGS", "Status": "ENABLED"}]' \
  --region us-east-1
```

---

## Containment Cheat Sheet (One-Liner Summary)

```bash
# 1. Kill vulnerable app & stop respawn
kubectl scale deployment health-dashboard --replicas=0 -n default
kubectl delete svc health-dashboard -n default

# 2. Invalidate compromised SA token
kubectl delete clusterrolebinding prod-admin-binding
kubectl delete pod payment-processor -n prod --grace-period=0 --force
kubectl delete sa prod-admin-sa -n prod

# 3. Terminate compromised node
aws ec2 terminate-instances --instance-ids <INSTANCE_ID> --region us-east-1
```
