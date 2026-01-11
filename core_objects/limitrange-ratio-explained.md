# Understanding maxLimitRequestRatio in Kubernetes LimitRange

## The Problem: Why Did "default-resources" Pod Get Rejected?

```
Error: pods "default-resources" is forbidden: cpu max limit to request 
ratio per Container is 4, but provided ratio is 5.000000
```

This error occurs because the **default values** in LimitRange violate its own **ratio rule**.

---

## What is maxLimitRequestRatio?

It's a **safety limit** that prevents containers from having too much "burst" capacity compared to their guaranteed allocation.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        maxLimitRequestRatio Explained                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   FORMULA:    limit ÷ request  ≤  maxLimitRequestRatio                      │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                                                                     │   │
│   │   Request: 100m CPU   ←── "I NEED at least this much"              │   │
│   │                            (guaranteed by scheduler)                │   │
│   │                                                                     │   │
│   │   Limit: 400m CPU     ←── "I CAN USE up to this much"              │   │
│   │                            (maximum burst allowed)                  │   │
│   │                                                                     │   │
│   │   Ratio: 400 ÷ 100 = 4.0   ✓ Within allowed ratio of 4            │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Does This Ratio Matter?

### Without Ratio Limit (Dangerous!)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Container A                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Request: 100m    Limit: 2000m    Ratio: 20x                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  The scheduler sees: "This needs 100m, I have space!"                       │
│  Reality: Container can burst to 2000m and STARVE other containers!        │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ Node: 4 CPU cores                                                      │ │
│  │ ┌───────────────────────────────────────────────────────────────────┐ │ │
│  │ │ Container A (bursting)   ████████████████████████████  2000m     │ │ │
│  │ │ Container B              ██                             STARVED!  │ │ │
│  │ │ Container C              ██                             STARVED!  │ │ │
│  │ │ Container D              ██                             STARVED!  │ │ │
│  │ └───────────────────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### With Ratio Limit of 4x (Safe!)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Container A                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Request: 100m    Limit: 400m    Ratio: 4x (max allowed)            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  Container can only burst to 4x its request - fair sharing maintained!     │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ Node: 4 CPU cores                                                      │ │
│  │ ┌───────────────────────────────────────────────────────────────────┐ │ │
│  │ │ Container A (bursting)   ████████                       400m      │ │ │
│  │ │ Container B              ████████                       400m      │ │ │
│  │ │ Container C              ████████                       400m      │ │ │
│  │ │ Container D              ████████                       400m      │ │ │
│  │ └───────────────────────────────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## The Original Bug Explained

### What We Had (WRONG):

```yaml
LimitRange:
  default:          # Default LIMITS
    cpu: 500m       # ← This is the limit
  
  defaultRequest:   # Default REQUESTS  
    cpu: 100m       # ← This is the request
  
  maxLimitRequestRatio:
    cpu: 4          # ← Max ratio allowed
```

**When a pod has no resources:**
```
Applied defaults:
  Request: 100m
  Limit:   500m
  
Ratio check: 500 ÷ 100 = 5.0  ← EXCEEDS 4!  ✗ REJECTED!
```

### What We Fixed (CORRECT):

```yaml
LimitRange:
  default:          # Default LIMITS
    cpu: 400m       # ← Changed to 400m (4x of 100m)
  
  defaultRequest:   # Default REQUESTS  
    cpu: 100m       # ← This stays the same
  
  maxLimitRequestRatio:
    cpu: 4          # ← Max ratio allowed
```

**When a pod has no resources:**
```
Applied defaults:
  Request: 100m
  Limit:   400m
  
Ratio check: 400 ÷ 100 = 4.0  ← EXACTLY 4!  ✓ ACCEPTED!
```

---

## Where Does This Apply?

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    LimitRange Scope                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  type: Container                                                     │   │
│  │  ─────────────────                                                   │   │
│  │  Applies to: EACH container individually                            │   │
│  │                                                                      │   │
│  │  In a Pod with 3 containers:                                        │   │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐                       │   │
│  │  │ Container1 │ │ Container2 │ │ Container3 │                       │   │
│  │  │            │ │            │ │            │                       │   │
│  │  │ limit/req  │ │ limit/req  │ │ limit/req  │  ← Each checked!     │   │
│  │  │  ≤ 4x ✓   │ │  ≤ 4x ✓   │ │  ≤ 4x ✓   │                       │   │
│  │  └────────────┘ └────────────┘ └────────────┘                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  type: Pod                                                           │   │
│  │  ─────────────                                                       │   │
│  │  Applies to: SUM of all containers in the pod                       │   │
│  │                                                                      │   │
│  │  Pod with 3 containers:                                             │   │
│  │  ┌──────────────────────────────────────────┐                       │   │
│  │  │  Container1 + Container2 + Container3    │                       │   │
│  │  │                                          │                       │   │
│  │  │  Total CPU ≤ max (4 cores)              │  ← Sum checked!       │   │
│  │  │  Total Memory ≤ max (4Gi)               │                       │   │
│  │  └──────────────────────────────────────────┘                       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Real-World Examples

### Example 1: Web Application (Light workload)
```yaml
resources:
  requests:
    cpu: 100m       # Need at least 0.1 CPU core
  limits:
    cpu: 400m       # Can burst to 0.4 CPU cores

# Ratio: 400 ÷ 100 = 4.0  ✅ ACCEPTED (exactly at limit)
```

### Example 2: API Server (Medium workload)
```yaml
resources:
  requests:
    cpu: 250m       # Need at least 0.25 CPU core
  limits:
    cpu: 1000m      # Can burst to 1 full CPU core (1000m = 1 core)

# Ratio: 1000 ÷ 250 = 4.0  ✅ ACCEPTED (exactly at limit)
```

### Example 3: Background Worker (High burst)
```yaml
resources:
  requests:
    cpu: 500m       # Need at least 0.5 CPU core
  limits:
    cpu: 2000m      # Can burst to 2 full CPU cores

# Ratio: 2000 ÷ 500 = 4.0  ✅ ACCEPTED (exactly at limit)
```

### Example 4: Database (Predictable workload)
```yaml
resources:
  requests:
    cpu: 1000m      # Need at least 1 CPU core
  limits:
    cpu: 2000m      # Can burst to 2 CPU cores (max in LimitRange)

# Ratio: 2000 ÷ 1000 = 2.0  ✅ ACCEPTED (well under limit)
```

### Example 5: Greedy Application (REJECTED!)
```yaml
resources:
  requests:
    cpu: 100m       # Claims to need only 0.1 core
  limits:
    cpu: 2000m      # Wants to burst to 2 full cores!

# Ratio: 2000 ÷ 100 = 20.0  ❌ REJECTED! Ratio far exceeds 4!
# This would let the pod "game" the scheduler
```

---

## Quick Reference Table

| Use Case | Request | Limit | Ratio | Result (max=4) |
|----------|---------|-------|-------|----------------|
| Minimal pod | 50m | 200m | 4.0 | ✅ Accepted |
| Light web app | 100m | 400m | 4.0 | ✅ Accepted |
| API server | 250m | 1000m | 4.0 | ✅ Accepted |
| Worker | 500m | 2000m | 4.0 | ✅ Accepted |
| Database | 1000m | 2000m | 2.0 | ✅ Accepted |
| Steady pod | 500m | 500m | 1.0 | ✅ Accepted |
| **Greedy pod** | 100m | 500m | 5.0 | ❌ **Rejected** |
| **Very greedy** | 100m | 1000m | 10.0 | ❌ **Rejected** |
| **Extreme** | 50m | 2000m | 40.0 | ❌ **Rejected** |

---

## Memory Examples

The same ratio applies to memory:

```yaml
resources:
  requests:
    memory: 128Mi    # Need at least 128 MiB
  limits:
    memory: 512Mi    # Can use up to 512 MiB

# Ratio: 512 ÷ 128 = 4.0  ✅ ACCEPTED
```

```yaml
resources:
  requests:
    memory: 256Mi    # Need at least 256 MiB
  limits:
    memory: 2Gi      # Can use up to 2 GiB (2048 MiB)

# Ratio: 2048 ÷ 256 = 8.0  ❌ REJECTED! Exceeds 4!
```



## How to Fix Ratio Violations

**Option 1: Increase Request**
```yaml
resources:
  requests:
    cpu: 200m      # Increased from 100m
  limits:
    cpu: 500m      # Stays same
# Ratio: 500 ÷ 200 = 2.5 ✓
```

**Option 2: Decrease Limit**
```yaml
resources:
  requests:
    cpu: 100m      # Stays same
  limits:
    cpu: 400m      # Decreased from 500m
# Ratio: 400 ÷ 100 = 4.0 ✓
```

**Option 3: Increase maxLimitRequestRatio (not recommended)**
```yaml
maxLimitRequestRatio:
  cpu: 5    # Allows more overcommitment - risky!
```

---

## Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  KEY TAKEAWAYS                                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. maxLimitRequestRatio = limit ÷ request                                  │
│                                                                              │
│  2. It prevents containers from having too much burst capacity              │
│                                                                              │
│  3. It applies to EACH CONTAINER individually (type: Container)            │
│                                                                              │
│  4. DEFAULT values must ALSO satisfy the ratio!                             │
│                                                                              │
│  5. If limit = 400m and request = 100m → ratio = 4.0                       │
│                                                                              │
│  6. A ratio of 4 means: "You can burst to 4x what you requested"           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```
