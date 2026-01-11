# LimitRange - Enforcing Resource Constraints in Kubernetes

## Overview

**LimitRange** is a Kubernetes policy object that enforces resource constraints at the **namespace level**. It automatically applies defaults and validates resource requests/limits for pods and containers.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Namespace: resource-constrained                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                       LimitRange: resource-limits                    │    │
│  │  ┌─────────────┬─────────────┬─────────────────────────────────┐   │    │
│  │  │ Defaults    │ Min/Max     │ Ratio Enforcement               │   │    │
│  │  │             │             │                                   │   │    │
│  │  │ • Requests  │ • CPU Range │ • Limit/Request ≤ 4x            │   │    │
│  │  │ • Limits    │ • Mem Range │                                   │   │    │
│  │  └─────────────┴─────────────┴─────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                       │
│  │   Pod A      │  │   Pod B      │  │   Pod C      │                       │
│  │  (defaults)  │  │  (explicit)  │  │  (rejected)  │                       │
│  │      ✓       │  │      ✓       │  │      ✗       │                       │
│  └──────────────┘  └──────────────┘  └──────────────┘                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Use LimitRange?

### The Problem

Without resource constraints:

| Issue | Impact |
|-------|--------|
| **Noisy Neighbors** | One pod consumes all resources, starving others |
| **OOM Kills** | Node runs out of memory, killing random pods |
| **CPU Throttling** | Unpredictable performance across workloads |
| **Cluster Instability** | Nodes become unresponsive under pressure |

### The Solution

LimitRange provides **namespace-level governance**:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     LimitRange Capabilities                          │
├──────────────────────┬──────────────────────────────────────────────┤
│ Feature              │ Benefit                                       │
├──────────────────────┼──────────────────────────────────────────────┤
│ Default Resources    │ Containers always have requests/limits       │
│ Min Constraints      │ Prevent undersized, unstable pods            │
│ Max Constraints      │ Prevent oversized, resource-hogging pods     │
│ Ratio Limits         │ Control overcommitment                       │
└──────────────────────┴──────────────────────────────────────────────┘
```

---

## LimitRange Types

### Container Limits

Applied to **each container individually**:

```yaml
spec:
  limits:
    - type: Container
      default:          # Applied if limits not specified
        cpu: 500m
        memory: 512Mi
      defaultRequest:   # Applied if requests not specified
        cpu: 100m
        memory: 128Mi
      max:              # Maximum allowed per container
        cpu: 2
        memory: 2Gi
      min:              # Minimum required per container
        cpu: 50m
        memory: 64Mi
      maxLimitRequestRatio:
        cpu: 4
        memory: 4
```

### Pod Limits

Applied to the **sum of all containers** in a pod:

```yaml
spec:
  limits:
    - type: Pod
      max:
        cpu: 4          # Total pod CPU limit
        memory: 4Gi     # Total pod memory limit
```

### PersistentVolumeClaim Limits

Control storage requests:

```yaml
spec:
  limits:
    - type: PersistentVolumeClaim
      max:
        storage: 10Gi
      min:
        storage: 1Gi
```

---

## How LimitRange Works

### Request Flow

```
┌──────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  Pod Create  │─────▶│  LimitRange      │─────▶│  Admission      │
│  Request     │      │  Webhook         │      │  Decision       │
└──────────────┘      └─────────┬────────┘      └────────┬────────┘
                                │                        │
                    ┌───────────┴───────────┐            │
                    ▼                       ▼            ▼
              ┌───────────┐          ┌───────────┐  ┌─────────┐
              │  Apply    │          │  Validate │  │ Accept  │
              │  Defaults │          │  Ranges   │  │   or    │
              └───────────┘          └───────────┘  │ Reject  │
                                                    └─────────┘
```

### Validation Rules

| Check | Condition | Result |
|-------|-----------|--------|
| **Min Check** | `request < min` | ❌ Rejected |
| **Max Check** | `limit > max` | ❌ Rejected |
| **Ratio Check** | `limit/request > maxRatio` | ❌ Rejected |
| **All Pass** | Within bounds | ✅ Accepted |

---

## Examples

### Example 1: Pod Without Resources

```yaml
# What you write:
spec:
  containers:
    - name: app
      image: nginx
      # No resources!

# What Kubernetes sees (after LimitRange):
spec:
  containers:
    - name: app
      image: nginx
      resources:
        requests:
          cpu: 100m      # ← defaultRequest
          memory: 128Mi
        limits:
          cpu: 500m      # ← default
          memory: 512Mi
```

### Example 2: Valid Pod

```yaml
spec:
  containers:
    - name: app
      image: nginx
      resources:
        requests:
          cpu: 200m       # ✓ ≥ min (50m), ≤ max (2)
          memory: 256Mi   # ✓ ≥ min (64Mi), ≤ max (2Gi)
        limits:
          cpu: 400m       # ✓ 2x request ≤ 4x max ratio
          memory: 512Mi   # ✓ 2x request ≤ 4x max ratio
```

### Example 3: Rejected Pod (Exceeds Max)

```yaml
spec:
  containers:
    - name: app
      image: nginx
      resources:
        requests:
          cpu: 3          # ✗ Exceeds max of 2
          memory: 3Gi     # ✗ Exceeds max of 2Gi

# Error: pods "too-big" is forbidden:
#   maximum cpu usage per Container is 2, but limit is 3
```

### Example 4: Rejected Pod (Bad Ratio)

```yaml
spec:
  containers:
    - name: app
      image: nginx
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 1000m      # ✗ 10x request, exceeds 4x ratio
          memory: 1Gi     # ✗ 8x request, exceeds 4x ratio

# Error: cpu max limit to request ratio is 4,
#        but provided ratio is 10.000000
```

---

## LimitRange vs ResourceQuota

| Feature | LimitRange | ResourceQuota |
|---------|------------|---------------|
| **Scope** | Per container/pod | Entire namespace |
| **Defaults** | ✓ Yes | ✗ No |
| **Min/Max** | Per resource | ✗ No |
| **Total Limits** | ✗ No | ✓ Yes |
| **Count Limits** | ✗ No | ✓ Yes |

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Namespace                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ResourceQuota: "Total namespace budget"                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ Total CPU: 10 cores  │  Total Memory: 20Gi  │  Max Pods: 50        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  LimitRange: "Per-pod/container rules"                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ Container: 50m-2 CPU  │  Pod Max: 4 CPU  │  Ratio: ≤4x            │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Use together** for comprehensive resource governance!

---

## Common Patterns

### 1. Development Namespace

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: dev-limits
spec:
  limits:
    - type: Container
      default:
        cpu: 200m
        memory: 256Mi
      defaultRequest:
        cpu: 50m
        memory: 64Mi
      max:
        cpu: 1
        memory: 1Gi
```

### 2. Production Namespace

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: prod-limits
spec:
  limits:
    - type: Container
      default:
        cpu: 500m
        memory: 512Mi
      defaultRequest:
        cpu: 200m
        memory: 256Mi
      max:
        cpu: 4
        memory: 8Gi
      min:
        cpu: 100m
        memory: 128Mi
      maxLimitRequestRatio:
        cpu: 2
        memory: 2
```

### 3. Batch Job Namespace

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: batch-limits
spec:
  limits:
    - type: Container
      max:
        cpu: 8
        memory: 16Gi
    - type: Pod
      max:
        cpu: 16
        memory: 32Gi
```

---

## Best Practices

| Practice | Rationale |
|----------|-----------|
| **Always set defaults** | Ensures no container runs without limits |
| **Set reasonable min values** | Prevents pods from being too small to function |
| **Keep ratio ≤ 4x** | Prevents over-commitment and ensures fair scheduling |
| **Combine with ResourceQuota** | LimitRange per-pod + Quota for total namespace |
| **Document your limits** | Help developers understand constraints |

---

## Verification Commands

```bash
# View LimitRange details
kubectl describe limitrange resource-limits -n resource-constrained

# Check all pods in namespace
kubectl get pods -n resource-constrained

# See applied resources for a pod
kubectl get pod <pod-name> -n resource-constrained -o yaml | grep -A 10 resources

# Watch for events (shows rejections)
kubectl get events -n resource-constrained --sort-by='.lastTimestamp'
```

---

## Quick Reference

```
┌────────────────────────────────────────────────────────────────────┐
│ LIMITRANGE QUICK REFERENCE                                          │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Types: Container | Pod | PersistentVolumeClaim                    │
│                                                                     │
│  Container Properties:                                              │
│  • default           → Default limits                               │
│  • defaultRequest    → Default requests                             │
│  • max               → Maximum allowed                              │
│  • min               → Minimum required                             │
│  • maxLimitRequestRatio → Max limit/request ratio                  │
│                                                                     │
│  Pod Properties:                                                    │
│  • max               → Sum of all containers                        │
│  • min               → Sum of all containers                        │
│                                                                     │
│  Common Commands:                                                   │
│  kubectl describe limitrange <name> -n <namespace>                 │
│  kubectl get limitrange -A                                         │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```
