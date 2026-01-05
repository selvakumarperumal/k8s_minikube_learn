# PostgreSQL StatefulSet Deployment Flow

This document explains what happens step-by-step when you run:

```bash
kubectl apply -f statefulset-postgresql.yaml
```

---

## Overview: What Gets Created

```mermaid
graph TB
    subgraph "kubectl apply -f statefulset-postgresql.yaml"
        CMD[kubectl apply]
    end
    
    CMD --> SVC1[Service: postgres<br/>Headless]
    CMD --> SVC2[Service: postgres-lb<br/>ClusterIP]
    CMD --> CM[ConfigMap: postgres-config]
    CMD --> SEC[Secret: postgres-secret]
    CMD --> STS[StatefulSet: postgres]
    
    STS --> POD0[Pod: postgres-0]
    STS --> POD1[Pod: postgres-1]
    STS --> POD2[Pod: postgres-2]
    
    STS --> PVC0[PVC: postgres-storage-postgres-0]
    STS --> PVC1[PVC: postgres-storage-postgres-1]
    STS --> PVC2[PVC: postgres-storage-postgres-2]
```

---

## Step 1: API Server Receives the Request

```mermaid
sequenceDiagram
    participant User
    participant kubectl
    participant APIServer as API Server
    participant etcd
    
    User->>kubectl: kubectl apply -f statefulset-postgresql.yaml
    kubectl->>APIServer: POST /apis/v1/services<br/>POST /apis/apps/v1/statefulsets
    APIServer->>etcd: Store resource definitions
    etcd-->>APIServer: Acknowledged
    APIServer-->>kubectl: Resources created
    kubectl-->>User: service/postgres created<br/>statefulset/postgres created
```

---

## Step 2: StatefulSet Controller Takes Action

```mermaid
flowchart TD
    subgraph Control Plane
        STS_CTRL[StatefulSet Controller]
        SCHED[Scheduler]
    end
    
    subgraph etcd
        STS_DEF[StatefulSet Definition<br/>replicas: 3]
    end
    
    STS_CTRL -->|Watches| STS_DEF
    STS_CTRL -->|"Current Pods: 0<br/>Desired Pods: 3<br/>Need to create!"| CREATE
    
    CREATE[Create Pod postgres-0]
    CREATE --> SCHED
    SCHED -->|Assign to Node| NODE[Worker Node]
```

---

## Step 3: Sequential Pod Creation (OrderedReady)

This is the KEY difference from Deployments. Pods are created **one at a time**, waiting for each to be Ready.

```mermaid
sequenceDiagram
    participant STS as StatefulSet Controller
    participant Node as Worker Node
    participant PVC as PVC Controller
    
    Note over STS: Start with 0 pods, need 3
    
    STS->>PVC: Create PVC: postgres-storage-postgres-0
    PVC-->>STS: PVC Bound
    STS->>Node: Create Pod: postgres-0
    Node-->>STS: Pod Running
    Note over Node: Wait for Readiness Probe...
    Node-->>STS: Pod Ready ✓
    
    Note over STS: 1 pod ready, need 3
    
    STS->>PVC: Create PVC: postgres-storage-postgres-1
    PVC-->>STS: PVC Bound
    STS->>Node: Create Pod: postgres-1
    Node-->>STS: Pod Running
    Note over Node: Wait for Readiness Probe...
    Node-->>STS: Pod Ready ✓
    
    Note over STS: 2 pods ready, need 3
    
    STS->>PVC: Create PVC: postgres-storage-postgres-2
    PVC-->>STS: PVC Bound
    STS->>Node: Create Pod: postgres-2
    Node-->>STS: Pod Running
    Note over Node: Wait for Readiness Probe...
    Node-->>STS: Pod Ready ✓
    
    Note over STS: 3 pods ready ✓ Done!
```

---

## Step 4: Container Startup Inside Each Pod

```mermaid
flowchart TD
    subgraph "Pod: postgres-0"
        INIT[Container Starts]
        ENV[Load Environment Variables]
        MOUNT[Mount PVC at /var/lib/postgresql/data]
        PG_START[PostgreSQL Initializes]
        READY[Readiness Probe Passes]
    end
    
    INIT --> ENV
    ENV --> MOUNT
    MOUNT --> PG_START
    PG_START -->|pg_isready succeeds| READY
    
    subgraph "Environment Variables Loaded"
        E1[POSTGRES_DB=mydb]
        E2[POSTGRES_USER=admin]
        E3[POSTGRES_PASSWORD=supersecret123]
        E4[PGDATA=/var/lib/postgresql/data/pgdata]
    end
    
    ENV -.-> E1
    ENV -.-> E2
    ENV -.-> E3
    ENV -.-> E4
```

---

## Step 5: DNS Records Created by Headless Service

```mermaid
graph LR
    subgraph "Headless Service: postgres"
        DNS[DNS Records Created]
    end
    
    DNS --> R0["postgres-0.postgres.default.svc.cluster.local"]
    DNS --> R1["postgres-1.postgres.default.svc.cluster.local"]
    DNS --> R2["postgres-2.postgres.default.svc.cluster.local"]
    
    R0 --> IP0[Pod IP: 10.244.0.10]
    R1 --> IP1[Pod IP: 10.244.0.11]
    R2 --> IP2[Pod IP: 10.244.0.12]
```

---

## Step 6: Client Connection Flow

```mermaid
flowchart TD
    CLIENT[Client Application]
    
    subgraph "Option 1: Load Balanced (postgres-lb)"
        LB[Service: postgres-lb<br/>ClusterIP: 10.96.100.50]
    end
    
    subgraph "Option 2: Direct Pod Access (postgres)"
        HEADLESS[Headless Service]
        DNS0[postgres-0.postgres...]
        DNS1[postgres-1.postgres...]
    end
    
    CLIENT -->|"Connect to postgres-lb:5432"| LB
    LB -->|Round Robin| POD0[postgres-0]
    LB -->|Round Robin| POD1[postgres-1]
    LB -->|Round Robin| POD2[postgres-2]
    
    CLIENT -->|"Connect to postgres-0.postgres:5432"| DNS0
    DNS0 --> POD0
    CLIENT -->|"Connect to postgres-1.postgres:5432"| DNS1
    DNS1 --> POD1
```

---

## What Happens When a Pod Crashes?

```mermaid
sequenceDiagram
    participant STS as StatefulSet Controller
    participant Node as Worker Node
    participant PVC as Existing PVC
    
    Note over Node: postgres-0 crashes!
    Node-->>STS: Pod postgres-0 terminated
    
    Note over STS: Current: 2 pods<br/>Desired: 3 pods
    
    STS->>Node: Create Pod: postgres-0 (same name!)
    Note over STS: Uses existing PVC
    STS->>PVC: Attach PVC: postgres-storage-postgres-0
    PVC-->>STS: Already exists, reattach
    
    Node-->>STS: Pod Running
    Node-->>STS: Pod Ready ✓
    
    Note over Node: Data preserved!<br/>Same hostname, same storage
```

---

## Scaling Up (replicas: 3 → 5)

```bash
kubectl scale statefulset postgres --replicas=5
```

```mermaid
flowchart LR
    subgraph "Before: 3 Replicas"
        P0[postgres-0]
        P1[postgres-1]
        P2[postgres-2]
    end
    
    SCALE[Scale to 5]
    
    subgraph "After: 5 Replicas"
        P0_2[postgres-0]
        P1_2[postgres-1]
        P2_2[postgres-2]
        P3[postgres-3 NEW]
        P4[postgres-4 NEW]
    end
    
    P0 --> SCALE --> P0_2
    P1 --> SCALE --> P1_2
    P2 --> SCALE --> P2_2
    SCALE --> P3
    SCALE --> P4
    
    Note1[Created in order:<br/>postgres-3 first<br/>then postgres-4]
```

---

## Scaling Down (replicas: 5 → 2)

```bash
kubectl scale statefulset postgres --replicas=2
```

```mermaid
flowchart LR
    subgraph "Before: 5 Replicas"
        P0[postgres-0]
        P1[postgres-1]
        P2[postgres-2]
        P3[postgres-3]
        P4[postgres-4]
    end
    
    SCALE[Scale to 2]
    
    subgraph "After: 2 Replicas"
        P0_2[postgres-0]
        P1_2[postgres-1]
    end
    
    P0 --> SCALE --> P0_2
    P1 --> SCALE --> P1_2
    P2 --> SCALE --> DELETED
    P3 --> SCALE --> DELETED
    P4 --> SCALE --> DELETED
    
    DELETED[❌ Deleted in reverse:<br/>postgres-4 first<br/>then postgres-3<br/>then postgres-2]
    
    Note2[⚠️ PVCs NOT deleted!<br/>Data preserved for scale-up]
```

---

## Rolling Update Flow

```bash
kubectl set image statefulset/postgres postgres=postgres:14
```

```mermaid
sequenceDiagram
    participant STS as StatefulSet Controller
    participant P2 as postgres-2
    participant P1 as postgres-1
    participant P0 as postgres-0
    
    Note over STS: Update Strategy: RollingUpdate<br/>Updates in REVERSE order
    
    STS->>P2: Terminate postgres-2
    P2-->>STS: Terminated
    STS->>P2: Create postgres-2 with new image
    P2-->>STS: Ready ✓
    
    STS->>P1: Terminate postgres-1
    P1-->>STS: Terminated
    STS->>P1: Create postgres-1 with new image
    P1-->>STS: Ready ✓
    
    STS->>P0: Terminate postgres-0
    P0-->>STS: Terminated
    STS->>P0: Create postgres-0 with new image
    P0-->>STS: Ready ✓
    
    Note over STS: All pods updated!
```

---

## Cleanup: What Gets Deleted

```bash
kubectl delete -f statefulset-postgresql.yaml
```

```mermaid
graph TD
    DELETE[kubectl delete -f statefulset-postgresql.yaml]
    
    DELETE -->|"✓ Deleted"| SVC1[Service: postgres]
    DELETE -->|"✓ Deleted"| SVC2[Service: postgres-lb]
    DELETE -->|"✓ Deleted"| CM[ConfigMap: postgres-config]
    DELETE -->|"✓ Deleted"| SEC[Secret: postgres-secret]
    DELETE -->|"✓ Deleted"| STS[StatefulSet: postgres]
    DELETE -->|"✓ Deleted"| PODS[All Pods]
    
    DELETE -.->|"❌ NOT Deleted!"| PVC0[PVC: postgres-storage-postgres-0]
    DELETE -.->|"❌ NOT Deleted!"| PVC1[PVC: postgres-storage-postgres-1]
    DELETE -.->|"❌ NOT Deleted!"| PVC2[PVC: postgres-storage-postgres-2]
    
    NOTE[⚠️ PVCs must be deleted manually:<br/>kubectl delete pvc -l app=postgres]
```

---

## Complete Architecture Summary

```mermaid
graph TB
    subgraph External["🌐 External"]
        CLIENT[👤 Client Application]
    end
    
    subgraph Cluster["☸️ Kubernetes Cluster"]
        subgraph Services["🔗 Services"]
            LB[📡 postgres-lb<br/>ClusterIP: 10.96.x.x]
            HEADLESS[🔍 postgres<br/>ClusterIP: None]
        end
        
        subgraph Config["⚙️ Configuration"]
            CM[📋 ConfigMap<br/>postgres-config]
            SEC[🔐 Secret<br/>postgres-secret]
        end
        
        subgraph STS["🗃️ StatefulSet: postgres"]
            POD0[🟢 postgres-0<br/>Primary]
            POD1[🔵 postgres-1<br/>Replica]
            POD2[🔵 postgres-2<br/>Replica]
        end
        
        subgraph Storage["💾 Persistent Storage"]
            PVC0[📦 PVC-0<br/>2Gi]
            PVC1[📦 PVC-1<br/>2Gi]
            PVC2[📦 PVC-2<br/>2Gi]
        end
    end
    
    %% Client Traffic (Orange lines)
    CLIENT --> LB
    LB --> POD0
    LB --> POD1
    LB --> POD2
    
    %% DNS Resolution (Blue dashed lines)
    HEADLESS -.->|DNS| POD0
    HEADLESS -.->|DNS| POD1
    HEADLESS -.->|DNS| POD2
    
    %% ConfigMap injection (Purple lines)
    CM --> POD0
    CM --> POD1
    CM --> POD2
    
    %% Secret injection (Red lines)
    SEC --> POD0
    SEC --> POD1
    SEC --> POD2
    
    %% Storage mounting (Yellow lines)
    POD0 --> PVC0
    POD1 --> PVC1
    POD2 --> PVC2

    %% Node Styling
    style CLIENT fill:#e1f5fe,stroke:#01579b,stroke-width:2px,color:#01579b
    style LB fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#e65100
    style HEADLESS fill:#fff3e0,stroke:#e65100,stroke-width:2px,color:#e65100
    style CM fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px,color:#7b1fa2
    style SEC fill:#fce4ec,stroke:#c2185b,stroke-width:2px,color:#c2185b
    style POD0 fill:#c8e6c9,stroke:#2e7d32,stroke-width:3px,color:#1b5e20
    style POD1 fill:#bbdefb,stroke:#1565c0,stroke-width:2px,color:#0d47a1
    style POD2 fill:#bbdefb,stroke:#1565c0,stroke-width:2px,color:#0d47a1
    style PVC0 fill:#fff9c4,stroke:#f9a825,stroke-width:2px,color:#f57f17
    style PVC1 fill:#fff9c4,stroke:#f9a825,stroke-width:2px,color:#f57f17
    style PVC2 fill:#fff9c4,stroke:#f9a825,stroke-width:2px,color:#f57f17

    %% Link Styling (Colored Lines)
    %% Client to LB (Orange - Traffic)
    linkStyle 0 stroke:#e65100,stroke-width:3px
    %% LB to Pods (Orange - Traffic)
    linkStyle 1 stroke:#e65100,stroke-width:2px
    linkStyle 2 stroke:#e65100,stroke-width:2px
    linkStyle 3 stroke:#e65100,stroke-width:2px
    %% Headless DNS (Blue - DNS Resolution)
    linkStyle 4 stroke:#1565c0,stroke-width:2px,stroke-dasharray:5
    linkStyle 5 stroke:#1565c0,stroke-width:2px,stroke-dasharray:5
    linkStyle 6 stroke:#1565c0,stroke-width:2px,stroke-dasharray:5
    %% ConfigMap (Purple - Config Injection)
    linkStyle 7 stroke:#7b1fa2,stroke-width:2px
    linkStyle 8 stroke:#7b1fa2,stroke-width:2px
    linkStyle 9 stroke:#7b1fa2,stroke-width:2px
    %% Secret (Red/Pink - Secret Injection)
    linkStyle 10 stroke:#c2185b,stroke-width:2px
    linkStyle 11 stroke:#c2185b,stroke-width:2px
    linkStyle 12 stroke:#c2185b,stroke-width:2px
    %% PVC (Yellow - Storage)
    linkStyle 13 stroke:#f9a825,stroke-width:3px
    linkStyle 14 stroke:#f9a825,stroke-width:3px
    linkStyle 15 stroke:#f9a825,stroke-width:3px
```

### Color Legend

| Line Color | Connection Type | Description |
|------------|-----------------|-------------|
| 🟧 **Orange** | Client Traffic | Client → Service → Pods (network requests) |
| 🔵 **Blue Dashed** | DNS Resolution | Headless Service → Pods (DNS lookup) |
| 🟪 **Purple** | ConfigMap | Config injection into pods (env vars) |
| 🟥 **Pink/Red** | Secret | Secret injection into pods (passwords) |
| 🟨 **Yellow** | Storage | Pods → PVCs (persistent data mount) |

### Node Color Legend

| Color | Component Type | Description |
|-------|---------------|-------------|
| 🟦 Light Blue | Client | External application connecting to cluster |
| 🟧 Orange | Services | Network endpoints (LoadBalancer & Headless) |
| 🟪 Purple | ConfigMap | Non-sensitive configuration data |
| 🟥 Pink | Secret | Sensitive data (passwords) |
| 🟩 Green | Primary Pod | First pod (postgres-0), typically the leader |
| 🔵 Blue | Replica Pods | Secondary pods (postgres-1, postgres-2) |
| 🟨 Yellow | PVCs | Persistent storage volumes |

---

## Quick Reference Commands

| Action | Command |
|--------|---------|
| Deploy | `kubectl apply -f statefulset-postgresql.yaml` |
| Watch pods | `kubectl get pods -w -l app=postgres` |
| Check StatefulSet | `kubectl get statefulset postgres` |
| Check PVCs | `kubectl get pvc` |
| Connect to DB | `kubectl exec -it postgres-0 -- psql -U admin -d mydb` |
| Scale up | `kubectl scale statefulset postgres --replicas=5` |
| Scale down | `kubectl scale statefulset postgres --replicas=2` |
| Update image | `kubectl set image statefulset/postgres postgres=postgres:14` |
| Delete all | `kubectl delete -f statefulset-postgresql.yaml` |
| Delete PVCs | `kubectl delete pvc -l app=postgres` |
