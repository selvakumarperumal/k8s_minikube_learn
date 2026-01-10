# Init Containers Explained

## What are Init Containers?

**Init containers** are specialized containers that run **before** the main application containers start. They run to completion, one at a time, in order.

```mermaid
flowchart LR
    subgraph Pod["Pod Lifecycle"]
        I1["Init 1<br/>wait-for-db"] --> I2["Init 2<br/>check-db"]
        I2 --> I3["Init 3<br/>migration"]
        I3 --> I4["Init 4<br/>config"]
        I4 --> Main["Main Container<br/>app"]
    end
    
    style I1 fill:#ffb86c,stroke:#f1fa8c,color:#282a36
    style I2 fill:#ffb86c,stroke:#f1fa8c,color:#282a36
    style I3 fill:#ffb86c,stroke:#f1fa8c,color:#282a36
    style I4 fill:#ffb86c,stroke:#f1fa8c,color:#282a36
    style Main fill:#50fa7b,stroke:#8be9fd,color:#282a36
```

---

## Init vs Main Containers

| Feature | Init Containers | Main Containers |
|---------|-----------------|-----------------|
| **Run order** | Sequential (one at a time) | Parallel (all at once) |
| **Must complete** | ✅ Yes, before next starts | ❌ Run until terminated |
| **Readiness probes** | ❌ Not supported | ✅ Supported |
| **Restart behavior** | Pod restarts if fails | Depends on restartPolicy |
| **Use case** | Setup, dependencies | Application logic |

---

## How Init Containers Work

```mermaid
sequenceDiagram
    participant Scheduler
    participant Init1 as Init Container 1
    participant Init2 as Init Container 2
    participant Main as Main Container
    
    Scheduler->>Init1: Start init-1
    Init1->>Init1: Run to completion
    Init1-->>Scheduler: Success ✓
    
    Scheduler->>Init2: Start init-2
    Init2->>Init2: Run to completion
    Init2-->>Scheduler: Success ✓
    
    Scheduler->>Main: Start main container
    Main->>Main: Application runs
    
    Note over Scheduler,Main: If any init fails,<br/>pod restarts
```

---

## Common Use Cases

```mermaid
flowchart TB
    subgraph UseCases["Init Container Use Cases"]
        UC1["⏳ Wait for Dependencies<br/>Database, API, Service"]
        UC2["📥 Download Config<br/>From S3, Git, ConfigMap"]
        UC3["🗄️ Run Migrations<br/>Database schema updates"]
        UC4["🔐 Setup Permissions<br/>File permissions, certs"]
        UC5["📦 Clone Repos<br/>Git clone, fetch data"]
    end
    
    style UC1 fill:#50fa7b,stroke:#8be9fd,color:#282a36
    style UC2 fill:#ffb86c,stroke:#f1fa8c,color:#282a36
    style UC3 fill:#ff79c6,stroke:#bd93f9,color:#f8f8f2
    style UC4 fill:#8be9fd,stroke:#50fa7b,color:#282a36
    style UC5 fill:#bd93f9,stroke:#ff79c6,color:#f8f8f2
```

| Use Case | Example |
|----------|---------|
| **Wait for service** | `until nslookup mydb; do sleep 2; done` |
| **Download config** | `wget -O /config/app.conf http://config-server/config` |
| **Database migration** | `psql -c "CREATE TABLE..."` |
| **Git clone** | `git clone https://github.com/repo.git /data` |
| **Set permissions** | `chmod 600 /secrets/*` |

---

## Demo Architecture

```mermaid
flowchart TB
    subgraph InitContainers["Init Containers (Run in Order)"]
        I1["1️⃣ wait-for-db<br/>nslookup postgres-service"]
        I2["2️⃣ check-db<br/>pg_isready"]
        I3["3️⃣ run-migration<br/>CREATE TABLE"]
        I4["4️⃣ download-config<br/>Write app.conf"]
    end
    
    subgraph MainContainer["Main Container"]
        App["🚀 app<br/>Read config & run"]
    end
    
    subgraph SharedVolume["Shared Volume"]
        Vol["/config/app.conf"]
    end
    
    I1 --> I2 --> I3 --> I4 --> App
    I4 -->|writes| Vol
    App -->|reads| Vol
    
    style InitContainers fill:#282a36,stroke:#ffb86c,color:#f8f8f2
    style MainContainer fill:#282a36,stroke:#50fa7b,color:#f8f8f2
    style Vol fill:#8be9fd,stroke:#50fa7b,color:#282a36
```

---

## Pod Status During Init

Watch pod status change as init containers complete:

```
NAME        READY   STATUS     RESTARTS   AGE
init-demo   0/1     Init:0/4   0          5s    ← Init 1 running
init-demo   0/1     Init:1/4   0          10s   ← Init 2 running
init-demo   0/1     Init:2/4   0          15s   ← Init 3 running
init-demo   0/1     Init:3/4   0          20s   ← Init 4 running
init-demo   1/1     Running    0          25s   ← Main container running!
```

---

## Failure Behavior

```mermaid
flowchart TB
    Start["Pod Starts"] --> Init1["Init 1"]
    Init1 -->|Success| Init2["Init 2"]
    Init2 -->|Fail| Restart["Pod Restarts"]
    Restart --> Init1
    Init2 -->|Success| Init3["Init 3"]
    Init3 -->|Success| Main["Main Container"]
    
    style Restart fill:#ff5555,stroke:#ff79c6,color:#f8f8f2
    style Main fill:#50fa7b,stroke:#8be9fd,color:#282a36
```

If any init container fails:
1. Pod enters **CrashLoopBackOff** or restarts
2. All init containers run again **from the beginning**
3. This continues until success or backoff limit

---

## Quick Demo

### Step 1: Create PostgreSQL (Optional)

```bash
# Create PostgreSQL pod
kubectl run postgres --image=postgres:13-alpine \
  --env="POSTGRES_USER=admin" \
  --env="POSTGRES_PASSWORD=password" \
  --env="POSTGRES_DB=mydb" \
  --port=5432

# Expose as service
kubectl expose pod postgres --name=postgres-service --port=5432
```

### Step 2: Apply Init Containers Demo

```bash
kubectl apply -f init-containers-demo.yaml
```

### Step 3: Watch Progress

```bash
# Watch pod status
kubectl get pods -w

# You'll see:
# init-demo   0/1     Init:0/4   0          1s
# init-demo   0/1     Init:1/4   0          5s
# ... and so on
```

### Step 4: View Init Container Logs

```bash
# View each init container's logs
kubectl logs init-demo -c wait-for-db
kubectl logs init-demo -c check-db
kubectl logs init-demo -c run-migration
kubectl logs init-demo -c download-config

# View main container logs
kubectl logs init-demo -c app
```

### Step 5: Cleanup

```bash
kubectl delete pod init-demo
kubectl delete pod postgres
kubectl delete svc postgres-service
```

---

## Key Points

> [!IMPORTANT]
> - Init containers run **one at a time**, **in order**
> - All init containers must **succeed** before main container starts
> - Init containers **can use different images** than main container
> - Use **shared volumes** to pass data from init to main containers

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| `Init:0/4` stuck | First init container waiting | Check logs: `kubectl logs <pod> -c <init-container>` |
| `Init:CrashLoopBackOff` | Init container failing | Check logs for error |
| Main container not starting | Init not complete | Wait for all init containers |

### Debug Commands

```bash
# Describe pod to see init container status
kubectl describe pod init-demo

# View init container logs
kubectl logs init-demo -c wait-for-db

# View events
kubectl get events --sort-by='.lastTimestamp'
```

---

## Related Files

- [init-containers-demo.yaml](init-containers-demo.yaml) - Full working example
- [daemonset-simple.yaml](daemonset-simple.yaml) - DaemonSet example
