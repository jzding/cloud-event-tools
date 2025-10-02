# OAuth Security in Kubernetes: Why It Still Matters

## Your Valid Security Concern

You're absolutely correct that **any pod** in a Kubernetes cluster has access to:
```bash
/var/run/secrets/kubernetes.io/serviceaccount/token
```

This raises the question: **"What's the point of OAuth if any pod can get a token?"**

## The Answer: RBAC + Token Scoping + Issuer Validation

OAuth in Kubernetes provides security through **multiple layers**:

### 1. **RBAC (Role-Based Access Control)**

Each ServiceAccount has **specific permissions**. Not all tokens are equal:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: consumer-sa
  namespace: cloud-events
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: cloud-event-consumer-role
  namespace: cloud-events
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
- apiGroups: ["authentication.k8s.io"]
  resources: ["tokenreviews"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: cloud-event-consumer-binding
  namespace: cloud-events
subjects:
- kind: ServiceAccount
  name: consumer-sa
  namespace: cloud-events
roleRef:
  kind: Role
  name: cloud-event-consumer-role
  apiGroup: rbac.authorization.k8s.io
```

### 2. **Token Scoping and Validation**

The OAuth server validates **multiple claims**:

```go
// Token validation checks:
1. Issuer: "https://kubernetes.default.svc" (only Kubernetes tokens accepted)
2. Audience: "https://kubernetes.default.svc" (specific to this service)
3. Subject: "system:serviceaccount:cloud-events:consumer-sa" (specific ServiceAccount)
4. Expiration: Token must not be expired
5. Signature: Token must be cryptographically valid
```

### 3. **Practical Security Example**

Let's say you have these pods:

#### Pod A: `consumer-sa` ServiceAccount
```bash
# This token works for cloud-event-proxy
TOKEN_A=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
# Subject: system:serviceaccount:cloud-events:consumer-sa
# Permissions: Can create subscriptions (via RBAC)
```

#### Pod B: `default` ServiceAccount
```bash
# This token will be REJECTED
TOKEN_B=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
# Subject: system:serviceaccount:some-namespace:default
# Permissions: No RBAC rules for cloud-event-proxy operations
```

#### Pod C: `malicious-pod` ServiceAccount
```bash
# This token will be REJECTED
TOKEN_C=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
# Subject: system:serviceaccount:malicious-namespace:malicious-sa
# Permissions: No access to cloud-event-proxy operations
```

## Security Layers in Action

### Layer 1: Network Security
```
Pod → cloud-event-proxy: Requires mTLS certificate
❌ Most pods don't have the required client certificates
```

### Layer 2: OAuth Token Validation
```
cloud-event-proxy validates:
✅ Token signature (cryptographically valid?)
✅ Token issuer (from Kubernetes OAuth server?)
✅ Token audience (intended for this service?)
✅ Token expiration (not expired?)
✅ Token subject (from authorized ServiceAccount?)
```

### Layer 3: RBAC Authorization
```
Kubernetes API checks:
✅ Does this ServiceAccount have permission for this operation?
✅ Is this ServiceAccount allowed in this namespace?
✅ Are there any NetworkPolicies blocking this request?
```

## Why OAuth Still Provides Security

### 1. **Principle of Least Privilege**
- Only **specific ServiceAccounts** have permission to perform operations
- Random pods can't just use their default tokens

### 2. **Audit Trail**
- Every request is logged with the **specific ServiceAccount identity**
- You can trace exactly which pod made which request

### 3. **Token Lifecycle Management**
- ServiceAccount tokens can be **rotated**
- ServiceAccounts can be **disabled** or **deleted**
- Permissions can be **revoked** via RBAC

### 4. **Defense in Depth**
- **mTLS**: Prevents network-level attacks
- **OAuth**: Provides identity and authorization
- **RBAC**: Enforces fine-grained permissions
- **NetworkPolicies**: Control network access

## Real-World Attack Scenarios

### ❌ Attack Scenario 1: Pod Compromise
```bash
# Attacker compromises random pod
kubectl exec -it compromised-pod -- bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Try to create subscription
curl -k -H "Authorization: Bearer $TOKEN" \
  --cert /etc/client-certs/tls.crt \
  --key /etc/client-certs/tls.key \
  -X POST "https://cloud-event-proxy:9043/api/subscriptions"

# Result: REJECTED
# - No client certificates mounted
# - ServiceAccount has no RBAC permissions
# - Token subject not authorized
```

### ✅ Legitimate Access
```bash
# Authorized consumer pod
kubectl exec -it consumer-pod -- bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Create subscription
curl -k -H "Authorization: Bearer $TOKEN" \
  --cert /etc/cloud-event-consumer/client-certs/tls.crt \
  --key /etc/cloud-event-consumer/client-certs/tls.key \
  -X POST "https://cloud-event-proxy:9043/api/subscriptions"

# Result: SUCCESS
# - Valid client certificates
# - ServiceAccount has RBAC permissions
# - Token subject is authorized
```

## Enhanced Security Recommendations

### 1. **ServiceAccount Token Projection**
```yaml
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: consumer-sa
  volumes:
  - name: projected-token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 3600  # 1 hour expiration
          audience: cloud-event-proxy  # Specific audience
```

### 2. **NetworkPolicies**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cloud-event-proxy-access
spec:
  podSelector:
    matchLabels:
      app: cloud-event-proxy
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: authorized-consumer  # Only specific pods
    ports:
    - protocol: TCP
      port: 9043
```

### 3. **OPA/Gatekeeper Policies**
```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: allowedserviceaccounts
spec:
  crd:
    spec:
      names:
        kind: AllowedServiceAccounts
      validation:
        properties:
          allowedAccounts:
            type: array
            items:
              type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package allowedserviceaccounts
        violation[{"msg": msg}] {
          input.review.object.spec.serviceAccountName != input.parameters.allowedAccounts[_]
          msg := "ServiceAccount not in allowed list"
        }
```

## Conclusion

OAuth in Kubernetes provides security through:

1. **Identity Verification**: Who is making the request?
2. **Authorization**: What are they allowed to do?
3. **Audit**: What did they actually do?
4. **Lifecycle Management**: How do we revoke access?

While any pod can access *a* ServiceAccount token, only **authorized ServiceAccounts** with proper **RBAC permissions** and **client certificates** can successfully authenticate to protected services.

The security comes from the **combination** of:
- **mTLS** (network-level security)
- **OAuth** (identity and basic authorization)
- **RBAC** (fine-grained permissions)
- **NetworkPolicies** (network-level access control)

This creates a **defense-in-depth** security model where compromising a single layer doesn't grant full access.
