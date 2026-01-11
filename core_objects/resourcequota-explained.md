# ResourceQuota - Namespace-Wide Resource Budgets

## Overview

**ResourceQuota** limits the **total resources** consumed by all objects in a namespace. Think of it as a **budget** for your team or application.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Namespace: team-a                                   │
│                                                                              │
│   ResourceQuota: "Total budget for the namespace"                           │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  Total CPU Requests: 2 cores  │  Total Memory Requests: 4Gi        │   │
│   │  Total CPU Limits: 4 cores    │  Total Memory Limits: 8Gi          │   │
│   │  Max Pods: 10                 │  Max Services: 5                   │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐                       │
│   │ Pod 1   │  │ Pod 2   │  │ Pod 3   │  │ Pod 4   │  ... up to 10        │
│   │ 200m    │  │ 500m    │  │ 300m    │  │ 400m    │                       │
│   └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘                       │
│        │           │           │           │                                │
│        └───────────┴───────────┴───────────┘                                │
│                        │                                                     │
│                  Total: 1400m / 2000m (70% used)                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## ResourceQuota vs LimitRange

| Feature | LimitRange | ResourceQuota |
|---------|------------|---------------|
| **Scope** | Per container/pod | Entire namespace |
| **Purpose** | "Each pod can use X" | "All pods together can use Y" |
| **Defaults** | ✓ Yes | ✗ No |
| **Min/Max per pod** | ✓ Yes | ✗ No |
| **Total limits** | ✗ No | ✓ Yes |
| **Object counts** | ✗ No | ✓ Yes |

**Use together for complete governance:**
- **LimitRange**: Ensures each pod has reasonable requests/limits
- **ResourceQuota**: Ensures total consumption stays within budget

---

## What Can ResourceQuota Limit?

### Compute Resources

```yaml
spec:
  hard:
    requests.cpu: "2"        # Total CPU requests across all pods
    requests.memory: 4Gi     # Total memory requests across all pods
    limits.cpu: "4"          # Total CPU limits across all pods
    limits.memory: 8Gi       # Total memory limits across all pods
```

### Object Counts

```yaml
spec:
  hard:
    pods: "10"                    # Maximum number of pods
    services: "5"                 # Maximum number of services
    persistentvolumeclaims: "3"   # Maximum number of PVCs
    configmaps: "10"              # Maximum number of ConfigMaps
    secrets: "10"                 # Maximum number of Secrets
    replicationcontrollers: "5"   # Maximum number of RCs
    resourcequotas: "1"           # Maximum number of quotas (meta!)
```

### Storage Resources

```yaml
spec:
  hard:
    requests.storage: 100Gi                    # Total storage across all PVCs
    persistentvolumeclaims: "5"                # Max PVC count
    gold.storageclass.storage.k8s.io/requests.storage: 50Gi  # Per StorageClass
```

---

## How ResourceQuota Works

### Admission Flow

```
┌──────────────┐     ┌────────────────────┐     ┌─────────────────┐
│  Create Pod  │────▶│  ResourceQuota     │────▶│    Decision     │
│   Request    │     │  Admission Check   │     │                 │
└──────────────┘     └────────┬───────────┘     └────────┬────────┘
                              │                          │
                    ┌─────────┴─────────┐               │
                    ▼                   ▼               ▼
              ┌───────────┐       ┌───────────┐   ┌─────────┐
              │ Calculate │       │  Compare  │   │ Accept  │
              │ New Total │       │ vs Quota  │   │   or    │
              └───────────┘       └───────────┘   │ Reject  │
                                                  └─────────┘

Example:
  Quota: requests.cpu = 2 (2000m)
  Current usage: 1400m
  New pod requests: 800m
  New total: 2200m > 2000m → REJECTED!
```

### Important Rule

> **When ResourceQuota is enabled, ALL pods MUST specify resource requests/limits!**

Pods without resources will be **rejected**. To avoid this, use **LimitRange** to set defaults.

---

## Real-World Example

### Scenario: Team Budget

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-a
spec:
  hard:
    # Team can use up to 8 CPU cores total
    requests.cpu: "4"
    limits.cpu: "8"
    
    # Team can use up to 16Gi memory total
    requests.memory: 8Gi
    limits.memory: 16Gi
    
    # Team can have up to 20 pods
    pods: "20"
```

### Quota Consumption Over Time

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Team-A Quota Status                                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  CPU Requests (limit: 4 cores)                                              │
│  ████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  2.5/4 cores (62%)     │
│                                                                              │
│  Memory Requests (limit: 8Gi)                                               │
│  ██████████████████████████████░░░░░░░░░░░░░░░░░░░░  5Gi/8Gi (62%)         │
│                                                                              │
│  Pods (limit: 20)                                                           │
│  ████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  8/20 pods (40%)       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Checking Quota Status

```bash
# View quota usage
kubectl describe quota team-quota -n team-a

# Output:
Name:                   team-quota
Namespace:              team-a
Resource                Used    Hard
--------                ----    ----
configmaps              2       10
limits.cpu              1400m   4
limits.memory           1792Mi  8Gi
persistentvolumeclaims  0       3
pods                    3       10
requests.cpu            800m    2
requests.memory         896Mi   4Gi
secrets                 1       10
services                0       5
```

---

## Common Error Messages

### Exceeded CPU Quota
```
Error from server (Forbidden): pods "my-pod" is forbidden: 
exceeded quota: team-quota, requested: requests.cpu=1, 
used: requests.cpu=1800m, limited: requests.cpu=2
```

### Exceeded Pod Count
```
Error from server (Forbidden): pods "my-pod" is forbidden: 
exceeded quota: team-quota, requested: pods=1, 
used: pods=10, limited: pods=10
```

### Missing Resources (when quota is set)
```
Error from server (Forbidden): pods "my-pod" is forbidden: 
failed quota: team-quota: must specify limits.cpu,limits.memory,
requests.cpu,requests.memory
```

---

## Best Practices

| Practice | Rationale |
|----------|-----------|
| **Always pair with LimitRange** | Provides defaults so pods aren't rejected |
| **Set requests < limits quota** | Allows room for burst capacity |
| **Include object counts** | Prevents namespace pollution |
| **Monitor usage regularly** | Adjust quotas based on actual needs |
| **Use multiple quotas per scope** | Separate quotas for BestEffort, NotBestEffort |

---

## Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  KEY TAKEAWAYS                                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. ResourceQuota = Total budget for entire namespace                       │
│                                                                              │
│  2. LimitRange = Per-pod/container rules                                    │
│                                                                              │
│  3. When quota is set, pods MUST have resource specs (or use LimitRange)   │
│                                                                              │
│  4. Quota limits TOTAL consumption (sum of all pods)                        │
│                                                                              │
│  5. Can also limit object counts (pods, services, PVCs, etc.)              │
│                                                                              │
│  6. Check usage: kubectl describe quota <name> -n <namespace>              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```
