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

## Quick Reference Table

| Resource Config | Request | Limit | Ratio | Result (if max=4) |
|-----------------|---------|-------|-------|-------------------|
| Example 1 | 100m | 100m | 1.0 | ✅ Accepted |
| Example 2 | 100m | 200m | 2.0 | ✅ Accepted |
| Example 3 | 100m | 400m | 4.0 | ✅ Accepted |
| Example 4 | 100m | 401m | 4.01 | ❌ Rejected |
| Example 5 | 100m | 500m | 5.0 | ❌ Rejected |
| Example 6 | 200m | 500m | 2.5 | ✅ Accepted |
| Example 7 | 50m | 500m | 10.0 | ❌ Rejected |

---

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
