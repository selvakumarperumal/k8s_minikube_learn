# Kubernetes Workload & Application Management - Complete Lab

## Prerequisites Setup
```bash
# Ensure Minikube is running
minikube start --driver=docker

# Load images
minikube image load fastapi-app:v1

# Verify
kubectl cluster-info
kubectl get nodes
```

---

## Part 1: StatefulSet - Ordered, Stateful Workloads

**📚 What is a StatefulSet?**

StatefulSets are for applications that need:
- **Stable, unique network identifiers** - Each pod gets predictable name
- **Stable, persistent storage** - Each pod gets its own volume
- **Ordered deployment and scaling** - Pods created/deleted in sequence
- **Ordered, automated rolling updates** - Updates happen one at a time

**Deployment vs StatefulSet:**
```
Deployment:                    StatefulSet:
├─ app-abc123                  ├─ app-0 (first, persistent)
├─ app-def456                  ├─ app-1 (second, persistent)
└─ app-ghi789                  └─ app-2 (third, persistent)

Random names                   Ordered names
No storage guarantee           Persistent storage per pod
Parallel creation              Sequential creation
Stateless apps                 Stateful apps (databases, etc.)
```

### 1.1 Simple StatefulSet

**statefulset-simple.yaml**
```yaml
# Headless Service - Required for StatefulSet
# Provides stable network identity for each pod
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  labels:
    app: nginx
spec:
  ports:
  - port: 80
    name: web
  clusterIP: None  # Headless - no load balancing, direct pod access
  selector:
    app: nginx
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: "nginx-service"  # Must match headless service name
  replicas: 3
  
  # Pod Management Policy
  podManagementPolicy: OrderedReady  # Options: OrderedReady, Parallel
  # OrderedReady: Creates pods sequentially (web-0, then web-1, then web-2)
  # Parallel: Creates all pods at once (like Deployment)
  
  selector:
    matchLabels:
      app: nginx
  
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
          name: web
        
        # Mount persistent volume
        volumeMounts:
        - name: www
          mountPath: /usr/share/nginx/html
  
  # Volume Claim Templates - Creates PVC for each pod
  volumeClaimTemplates:
  - metadata:
      name: www
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
```

**🔍 StatefulSet Pod Naming:**
```
StatefulSet: web (replicas: 3)
Service: nginx-service (headless)

Pods:
├─ web-0
│  ├─ Hostname: web-0
│  ├─ DNS: web-0.nginx-service.default.svc.cluster.local
│  └─ PVC: www-web-0
│
├─ web-1
│  ├─ Hostname: web-1
│  ├─ DNS: web-1.nginx-service.default.svc.cluster.local
│  └─ PVC: www-web-1
│
└─ web-2
   ├─ Hostname: web-2
   ├─ DNS: web-2.nginx-service.default.svc.cluster.local
   └─ PVC: www-web-2
```

```bash
# Create StatefulSet
kubectl apply -f statefulset-simple.yaml

# Watch pods being created sequentially
kubectl get pods -w
# You'll see:
# web-0: Pending → Running (waits for this to be Ready)
# web-1: Pending → Running (then this starts)
# web-2: Pending → Running (then this starts)

# View StatefulSet
kubectl get statefulset
kubectl get sts  # Short name

# Describe StatefulSet
kubectl describe statefulset web
# Shows: Replicas, Pod Status, Events

# View pods with stable names
kubectl get pods -l app=nginx
# web-0, web-1, web-2 (ordered, predictable names)

# View PersistentVolumeClaims created automatically
kubectl get pvc
# www-web-0, www-web-1, www-web-2 (one per pod)

# View PersistentVolumes
kubectl get pv

# Test stable network identity
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# Inside debug pod:
nslookup web-0.nginx-service.default.svc.cluster.local
nslookup web-1.nginx-service.default.svc.cluster.local
nslookup web-2.nginx-service.default.svc.cluster.local
exit

# Write data to pod-0's persistent volume
kubectl exec web-0 -- sh -c 'echo "Hello from web-0" > /usr/share/nginx/html/index.html'

# Read data
kubectl exec web-0 -- cat /usr/share/nginx/html/index.html

# Delete pod-0 (test persistence)
kubectl delete pod web-0

# Watch pod recreation
kubectl get pods -w
# web-0 is recreated with SAME name and SAME PVC

# Verify data persisted
kubectl exec web-0 -- cat /usr/share/nginx/html/index.html
# Still shows: "Hello from web-0"

# Scale up
kubectl scale statefulset web --replicas=5
# web-3 and web-4 created sequentially

# Scale down
kubectl scale statefulset web --replicas=2
# web-4 deleted first, then web-3 (reverse order)

# Delete StatefulSet (keeps PVCs by default!)
kubectl delete statefulset web

# PVCs still exist
kubectl get pvc
# www-web-0, www-web-1, www-web-2 still present

# Delete PVCs manually
kubectl delete pvc www-web-0 www-web-1 www-web-2

# Delete service
kubectl delete service nginx-service
```

### 1.2 StatefulSet with Real Database (PostgreSQL)

**statefulset-postgresql.yaml**
```yaml
# Headless Service for StatefulSet
apiVersion: v1
kind: Service
metadata:
  name: postgres
  labels:
    app: postgres
spec:
  ports:
  - port: 5432
    name: postgres
  clusterIP: None
  selector:
    app: postgres
---
# Regular Service for client connections
apiVersion: v1
kind: Service
metadata:
  name: postgres-lb
  labels:
    app: postgres
spec:
  type: ClusterIP
  ports:
  - port: 5432
    targetPort: 5432
  selector:
    app: postgres
---
# ConfigMap for PostgreSQL configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-config
data:
  POSTGRES_DB: mydb
  POSTGRES_USER: admin
  PGDATA: /var/lib/postgresql/data/pgdata
---
# Secret for PostgreSQL password
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
type: Opaque
stringData:
  POSTGRES_PASSWORD: supersecret123
---
# StatefulSet for PostgreSQL
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:13
        
        ports:
        - containerPort: 5432
          name: postgres
        
        # Environment from ConfigMap and Secret
        envFrom:
        - configMapRef:
            name: postgres-config
        - secretRef:
            name: postgres-secret
        
        # Liveness probe
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U admin -d mydb
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        # Readiness probe
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U admin -d mydb
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        
        # Resources
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        
        # Volume mount
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
  
  # Persistent Volume Claim template
  volumeClaimTemplates:
  - metadata:
      name: postgres-storage
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 2Gi
```

**🔍 PostgreSQL StatefulSet Architecture:**
```
Client Application
│
├─► Service: postgres-lb (load balancer)
│   └─► Connects to any healthy pod
│
└─► Headless Service: postgres
    └─► Direct pod access for replication

Pods (in Minikube - single node):
├─ postgres-0
│  ├─ DNS: postgres-0.postgres.default.svc.cluster.local
│  ├─ Storage: postgres-storage-postgres-0 (2Gi)
│  └─ Role: Primary (in real setup)
│
├─ postgres-1
│  ├─ DNS: postgres-1.postgres.default.svc.cluster.local
│  ├─ Storage: postgres-storage-postgres-1 (2Gi)
│  └─ Role: Replica (in real setup)
│
└─ postgres-2
   ├─ DNS: postgres-2.postgres.default.svc.cluster.local
   ├─ Storage: postgres-storage-postgres-2 (2Gi)
   └─ Role: Replica (in real setup)

Note: True PostgreSQL replication requires additional configuration
(replication slots, pg_hba.conf, etc.)
```

```bash
# Create PostgreSQL StatefulSet
kubectl apply -f statefulset-postgresql.yaml

# Watch sequential pod creation
kubectl get pods -w

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod -l app=postgres --timeout=300s

# View StatefulSet
kubectl get statefulset postgres

# View PVCs
kubectl get pvc
# postgres-storage-postgres-0, postgres-storage-postgres-1, postgres-storage-postgres-2

# Connect to postgres-0
kubectl exec -it postgres-0 -- psql -U admin -d mydb

# Inside PostgreSQL:
-- Create a table
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  email VARCHAR(100)
);

-- Insert data
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com');

-- Query data
SELECT * FROM users;

-- Exit
\q

# Delete postgres-0 pod
kubectl delete pod postgres-0

# Wait for recreation
kubectl wait --for=condition=ready pod/postgres-0 --timeout=60s

# Verify data persisted
kubectl exec -it postgres-0 -- psql -U admin -d mydb -c "SELECT * FROM users;"
# Data still present!

# Test DNS resolution from another pod
kubectl run -it --rm psql-client --image=postgres:13 --restart=Never -- sh
# Inside client:
psql -h postgres-0.postgres.default.svc.cluster.local -U admin -d mydb -c "SELECT * FROM users;"
psql -h postgres-1.postgres.default.svc.cluster.local -U admin -d mydb
# Each pod has independent data
exit

# Clean up
kubectl delete -f statefulset-postgresql.yaml
kubectl delete pvc -l app=postgres
```

### 1.3 StatefulSet Update Strategies

**statefulset-update.yaml**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: app-service
spec:
  ports:
  - port: 80
  clusterIP: None
  selector:
    app: myapp
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: myapp
spec:
  serviceName: app-service
  replicas: 3
  
  # Update Strategy
  updateStrategy:
    type: RollingUpdate  # Options: RollingUpdate, OnDelete
    rollingUpdate:
      partition: 0  # Only update pods >= this ordinal
      # partition: 2 means only myapp-2 gets updated
      # partition: 0 means all pods get updated (default)
  
  selector:
    matchLabels:
      app: myapp
  
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: nginx
        image: nginx:1.20  # Will update to 1.21
        ports:
        - containerPort: 80
        volumeMounts:
        - name: data
          mountPath: /data
  
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
```

**🔍 StatefulSet Update Process:**
```
RollingUpdate (default):
├─ Updates pods in reverse order
├─ myapp-2 updated first
├─ Wait for myapp-2 to be Ready
├─ myapp-1 updated next
├─ Wait for myapp-1 to be Ready
└─ myapp-0 updated last

OnDelete:
├─ No automatic updates
├─ Must manually delete pods
└─ New pods created with new spec

Partition (Canary Updates):
partition: 2
├─ myapp-2 updated (ordinal >= 2)
├─ myapp-1 NOT updated
└─ myapp-0 NOT updated
```

```bash
# Create StatefulSet
kubectl apply -f statefulset-update.yaml

# Wait for all pods ready
kubectl wait --for=condition=ready pod -l app=myapp --timeout=60s

# Check current image version
kubectl get pod myapp-0 -o jsonpath='{.spec.containers[0].image}'
# nginx:1.20

# Update image
kubectl set image statefulset/myapp nginx=nginx:1.21

# Watch rolling update (reverse order)
kubectl get pods -w
# myapp-2 terminates first, then recreated with new image
# Then myapp-1, then myapp-0

# Check rollout status
kubectl rollout status statefulset/myapp

# Verify new image
kubectl get pods -l app=myapp -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# Test canary update with partition
kubectl patch statefulset myapp -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'

# Update image again
kubectl set image statefulset/myapp nginx=nginx:1.22

# Only myapp-2 gets updated!
kubectl get pods -l app=myapp -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
# myapp-0: nginx:1.21
# myapp-1: nginx:1.21
# myapp-2: nginx:1.22

# If satisfied, roll out to all
kubectl patch statefulset myapp -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'

# Clean up
kubectl delete -f statefulset-update.yaml
kubectl delete pvc -l app=myapp
```

**💡 StatefulSet Best Practices:**

```yaml
# ✅ GOOD: Use StatefulSets for
- Databases (PostgreSQL, MySQL, MongoDB)
- Message queues (Kafka, RabbitMQ)
- Distributed systems (Zookeeper, Consul, etcd)
- Applications requiring stable network identity

# ❌ BAD: Don't use StatefulSets for
- Stateless web applications (use Deployment)
- Workers that don't need identity (use Deployment)
- Jobs/CronJobs (use Job/CronJob)

# ✅ GOOD: Always use headless service
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  clusterIP: None  # Required for StatefulSet

# ✅ GOOD: Set podManagementPolicy
spec:
  podManagementPolicy: OrderedReady  # Default, safest
  # Use Parallel only if order doesn't matter

# ✅ GOOD: Use partition for canary updates
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 2  # Test on highest ordinal first
```

---

## Part 2: DaemonSet - Node-Level Agents

**📚 What is a DaemonSet?**

DaemonSet ensures that a copy of a pod runs on **all (or some) nodes** in the cluster.

**Use Cases:**
- **Node monitoring** - Prometheus Node Exporter on every node
- **Log collection** - Fluentd/Logstash on every node
- **Storage daemons** - Ceph, GlusterFS on storage nodes
- **Network plugins** - CNI plugins on every node
- **Security agents** - Intrusion detection on every node

**DaemonSet vs Deployment:**
```
Deployment:                    DaemonSet:
├─ Runs N replicas             ├─ Runs 1 pod per node
├─ Pods on any nodes           ├─ Pod on EVERY node
├─ User specifies count        ├─ Kubernetes manages count
└─ For applications            └─ For node-level services

Example:                       Example:
3 replicas on 5 nodes          5 pods on 5 nodes (1 per node)
```

### 2.1 Simple DaemonSet

**daemonset-simple.yaml**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-logger
  labels:
    app: node-logger
spec:
  selector:
    matchLabels:
      app: node-logger
  
  # Update strategy
  updateStrategy:
    type: RollingUpdate  # Options: RollingUpdate, OnDelete
    rollingUpdate:
      maxUnavailable: 1  # Update one node at a time
  
  template:
    metadata:
      labels:
        app: node-logger
    spec:
      # Run on all nodes (including control plane in Minikube)
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      
      containers:
      - name: logger
        image: busybox
        command:
        - sh
        - -c
        - |
          echo "Node logger starting on node: $(hostname)"
          echo "Node name: $NODE_NAME"
          echo "Pod name: $POD_NAME"
          echo "Namespace: $POD_NAMESPACE"
          while true; do
            echo "[$(date)] Monitoring node $NODE_NAME..."
            sleep 30
          done
        
        # Environment variables from downward API
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
```

**🔍 DaemonSet Pod Placement:**
```
Kubernetes Cluster (Minikube = 1 node)
│
└─ Node: minikube
   └─ DaemonSet pod: node-logger-xxxxx

Multi-node cluster example:
│
├─ Node: node-1
│  └─ DaemonSet pod: node-logger-xxxxx
│
├─ Node: node-2
│  └─ DaemonSet pod: node-logger-yyyyy
│
└─ Node: node-3
   └─ DaemonSet pod: node-logger-zzzzz

New node added?
└─ DaemonSet automatically schedules pod on new node

Node removed?
└─ DaemonSet pod terminated automatically
```

```bash
# Create DaemonSet
kubectl apply -f daemonset-simple.yaml

# View DaemonSet
kubectl get daemonset
kubectl get ds  # Short name
# Shows: DESIRED=1, CURRENT=1, READY=1 (in Minikube with 1 node)

# Describe DaemonSet
kubectl describe daemonset node-logger
# Shows: Pods on each node, Update strategy, Events

# View pods
kubectl get pods -l app=node-logger -o wide
# Shows pod running on minikube node

# View logs
kubectl logs -l app=node-logger
# Shows node monitoring logs

# Follow logs
kubectl logs -l app=node-logger -f

# Check which node pod is running on
kubectl get pods -l app=node-logger -o jsonpath='{.items[0].spec.nodeName}'
# Returns: minikube

# In multi-node cluster, you'd see one pod per node:
# kubectl get pods -l app=node-logger -o wide
# NAME                  NODE
# node-logger-xxxxx     node-1
# node-logger-yyyyy     node-2
# node-logger-zzzzz     node-3

# Update DaemonSet (rolling update)
kubectl set image daemonset/node-logger logger=busybox:1.35

# Watch update
kubectl rollout status daemonset/node-logger

# Delete DaemonSet
kubectl delete daemonset node-logger
```

### 2.2 DaemonSet with Node Selector

**daemonset-node-selector.yaml**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: gpu-monitor
  labels:
    app: gpu-monitor
spec:
  selector:
    matchLabels:
      app: gpu-monitor
  
  template:
    metadata:
      labels:
        app: gpu-monitor
    spec:
      # Only run on nodes with GPU
      nodeSelector:
        gpu: "true"  # Only nodes with label gpu=true
      
      containers:
      - name: monitor
        image: busybox
        command:
        - sh
        - -c
        - |
          echo "GPU monitor running on: $(hostname)"
          while true; do
            echo "[$(date)] Monitoring GPU..."
            sleep 60
          done
        
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
```

```bash
# Create DaemonSet
kubectl apply -f daemonset-node-selector.yaml

# Check DaemonSet status
kubectl get daemonset gpu-monitor
# DESIRED=0 (no nodes with gpu=true label)

# Label minikube node as GPU node
kubectl label nodes minikube gpu=true

# Check again
kubectl get daemonset gpu-monitor
# DESIRED=1, CURRENT=1

# View pod
kubectl get pods -l app=gpu-monitor

# Remove label
kubectl label nodes minikube gpu-
# Pod is automatically terminated

# Re-add label
kubectl label nodes minikube gpu=true

# Clean up
kubectl delete daemonset gpu-monitor
```

### 2.3 Real-World DaemonSet - Log Collector

**daemonset-fluentd.yaml**
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: kube-system
  labels:
    app: fluentd-logging
spec:
  selector:
    matchLabels:
      app: fluentd-logging
  
  template:
    metadata:
      labels:
        app: fluentd-logging
    spec:
      # Service account for reading logs
      serviceAccountName: fluentd
      
      # Tolerations to run on all nodes
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      
      containers:
      - name: fluentd
        image: fluent/fluentd:v1.14-1
        
        env:
        - name: FLUENT_UID
          value: "0"
        
        resources:
          requests:
            cpu: 100m
            memory: 200Mi
          limits:
            cpu: 200m
            memory: 400Mi
        
        # Mount host paths to read logs
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: fluentd-config
          mountPath: /fluentd/etc
      
      volumes:
      # Host paths
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      # ConfigMap for Fluentd config
      - name: fluentd-config
        configMap:
          name: fluentd-config
---
# Service Account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fluentd
  namespace: kube-system
---
# ConfigMap for Fluentd configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  namespace: kube-system
data:
  fluent.conf: |
    <source>
      @type tail
      path /var/log/containers/*.log
      pos_file /var/log/fluentd-containers.log.pos
      tag kubernetes.*
      read_from_head true
      <parse>
        @type json
        time_format %Y-%m-%dT%H:%M:%S.%NZ
      </parse>
    </source>
    
    <match kubernetes.**>
      @type stdout
    </match>
```

```bash
# Create Fluentd DaemonSet
kubectl apply -f daemonset-fluentd.yaml

# Check DaemonSet in kube-system namespace
kubectl get daemonset -n kube-system fluentd

# View pods
kubectl get pods -n kube-system -l app=fluentd-logging

# View logs (shows container logs from all pods)
kubectl logs -n kube-system -l app=fluentd-logging --tail=50

# Clean up
kubectl delete -f daemonset-fluentd.yaml
```

**💡 DaemonSet Best Practices:**

```yaml
# ✅ GOOD: Use DaemonSets for
- Log collectors (Fluentd, Logstash)
- Monitoring agents (Prometheus Node Exporter, Datadog agent)
- Storage daemons (Ceph, GlusterFS)
- Network plugins (Calico, Weave)

# ✅ GOOD: Use tolerations to run on all nodes
tolerations:
- key: node-role.kubernetes.io/control-plane
  operator: Exists
  effect: NoSchedule

# ✅ GOOD: Use nodeSelector for specific nodes
nodeSelector:
  disktype: ssd  # Only on SSD nodes

# ✅ GOOD: Set resource limits
resources:
  requests:
    cpu: 100m
    memory: 200Mi
  limits:
    cpu: 200m
    memory: 400Mi

# ✅ GOOD: Use hostPath for node-level access
volumes:
- name: host-logs
  hostPath:
    path: /var/log
```

---

## Part 3: Init & Sidecar Containers

### 3.1 Init Containers - Startup Logic

**📚 Init Containers:**
- Run **before** main containers start
- Run **sequentially** (one after another)
- Must complete **successfully** (exit 0)
- Share volumes with main containers

**Use Cases:**
- Wait for dependencies (database, service)
- Download configuration/secrets
- Run database migrations
- Pre-populate data
- Setup/initialization tasks

**init-containers-demo.yaml**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-demo
spec:
  # Init containers run first (in order)
  initContainers:
  
  # 1. Wait for service
  - name: wait-for-db
    image: busybox:1.35
    command:
    - sh
    - -c
    - |
      echo "Waiting for database service..."
      until nslookup postgres-service.default.svc.cluster.local; do
        echo "Database not ready, waiting 2 seconds..."
        sleep 2
      done
      echo "Database service is ready!"
  
  # 2. Check database connection
  - name: check-db
    image: postgres:13
    command:
    - sh
    - -c
    - |
      echo "Checking database connection..."
      until pg_isready -h postgres-service -U admin; do
        echo "Database not accepting connections, waiting..."
        sleep 2
      done
      echo "Database is accepting connections!"
    env:
    - name: PGPASSWORD
      value: "password"
  
  # 3. Run migration
  - name: run-migration
    image: postgres:13
    command:
    - sh
    - -c
    - |
      echo "Running database migration..."
      psql -h postgres-service -U admin -d mydb -c "
        CREATE TABLE IF NOT EXISTS migrations (
          id SERIAL PRIMARY KEY,
          version VARCHAR(50),
          applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        INSERT INTO migrations (version) VALUES ('v1.0.0');
      "
      echo "Migration completed!"
    env:
    - name: PGPASSWORD
      value: "password"
  
  # 4. Download config
  - name: download-config
    image: busybox
    command:
    - sh
    - -c
    - |
      echo "Downloading configuration..."
      echo "api_key=secret123" > /config/app.conf
      echo "db_host=postgres-service" >> /config/app.conf
      echo "log_level=info" >> /config/app.conf
      ls -la /config/
    volumeMounts:
    - name: config-volume
      mountPath: /config
  
  # Main containers start ONLY after all init containers succeed
  containers:
  - name: app
    image: busybox
    command:
    - sh
    - -c
    - |
      echo "Application starting..."
      echo "Reading configuration:"
      cat /config/app.conf
      echo "Application ready to serve traffic"
      sleep 3600
    volumeMounts:
    - name: config-volume
      mountPath: /config
  
  volumes:
  - name: config-volume
    emptyDir: {}
```

**🔍 Init Container Execution Flow:**
```
Pod: init-demo

Timeline:
0s   ├─► Init Container 1: wait-for-db
     │   ├─ Checks DNS for postgres-service
     │   └─ Exit 0 (success)
     │
15s  ├─► Init Container 2: check-db
     │   ├─ Checks postgres connection
     │   └─ Exit 0 (success)
     │
30s  ├─► Init Container 3: run-migration
     │   ├─ Runs SQL migration
     │   └─ Exit 0 (success)
     │
45s  ├─► Init Container 4: download-config
     │   ├─ Downloads config to shared volume
     │   └─ Exit 0 (success)
     │
60s  └─► Main Container: app
         ├─ Reads config from shared volume
         └─ Starts serving traffic

If any init container fails (exit ≠ 0):
└─► Pod stuck in Init state, retries failed container
```

```bash
# First, create a postgres service for demo
kubectl create deployment postgres --image=postgres:13
kubectl expose deployment postgres --name=postgres-service --port=5432
kubectl set env deployment/postgres POSTGRES_PASSWORD=password POSTGRES_USER=admin POSTGRES_DB=mydb

# Wait for postgres to be ready
kubectl wait --for=condition=ready pod -l app=postgres --timeout=60s

# Create pod with init containers
kubectl apply -f init-containers-demo.yaml

# Watch pod phases
kubectl get pod init-demo --watch
# You'll see: Init:0/4, Init:1/4, Init:2/4, Init:3/4, Init:4/4, Running

# Check init container status
kubectl describe pod init-demo
# Look for "Init Containers:" section - shows status of each

# View logs from each init container
kubectl logs init-demo -c wait-for-db
kubectl logs init-demo -c check-db
kubectl logs init-demo -c run-migration
kubectl logs init-demo -c download-config

# View main container logs
kubectl logs init-demo -c app
# Should show: Configuration loaded, app starting

# Check config file created by init container
kubectl exec init-demo -- cat /config/app.conf

# Verify database migration
kubectl exec -it $(kubectl get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- psql -U admin -d mydb -c "SELECT * FROM migrations;"

# Clean up
kubectl delete pod init-demo
kubectl delete deployment postgres
kubectl delete service postgres-service
```

### 3.2 Sidecar Containers - Cross-Cutting Concerns

**📚 Sidecar Pattern:**

Sidecar containers run **alongside** the main container throughout the pod's lifetime.

**Common Patterns:**
1. **Log shipping** - Collect and forward logs
2. **Proxy/Ambassador** - Handle network traffic
3. **Adapter** - Transform/normalize data
4. **Configuration watcher** - Reload config without restart

**sidecar-logging.yaml**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-logging
spec:
  # Shared volume for logs
  volumes:
  - name: shared-logs
    emptyDir: {}
  
  containers:
  # Main application
  - name: app
    image: busybox
    command:
    - sh
    - -c
    - |
      echo "Application starting..."
      while true; do
        # Generate application logs
        echo "[$(date)] INFO: Processing request $RANDOM" >> /var/log/app.log
        echo "[$(date)] WARN: Cache miss for key-$RANDOM" >> /var/log/app.log
        sleep 2
      done
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
  
  # Sidecar: Log shipper
  - name: log-shipper
    image: busybox
    command:
    - sh
    - -c
    - |
      echo "Log shipper starting..."
      # Wait for log file
      while [ ! -f /var/log/app.log ]; do
        sleep 1
      done
      # Ship logs (in real scenario: send to Elasticsearch, Splunk, etc.)
      tail -f /var/log/app.log | while read line; do
        echo "[SHIPPED] $line"
        # In production: curl -X POST elasticsearch:9200/logs/_doc -d "$line"
      done
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
  
  # Sidecar: Log analyzer
  - name: log-analyzer
    image: busybox
    command:
    - sh
    - -c
    - |
      echo "Log analyzer starting..."
      while [ ! -f /var/log/app.log ]; do
        sleep 1
      done
      # Analyze logs for errors
      tail -f /var/log/app.log | while read line; do
        if echo "$line" | grep -q "ERROR\|WARN"; then
          echo "[ALERT] Found warning/error: $line"
        fi
      done
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
```

```bash
# Create pod with sidecars
kubectl apply -f sidecar-logging.yaml

# Wait for all containers to be ready
kubectl wait --for=condition=ready pod/sidecar-logging --timeout=60s

# View logs from main app
kubectl logs sidecar-logging -c app

# View logs from log shipper sidecar
kubectl logs sidecar-logging -c log-shipper
# Shows: [SHIPPED] prefix on all logs

# View logs from log analyzer sidecar
kubectl logs sidecar-logging -c log-analyzer
# Shows: [ALERT] only for WARN/ERROR lines

# Follow all logs simultaneously (in separate terminals)
kubectl logs sidecar-logging -c app -f
kubectl logs sidecar-logging -c log-shipper -f
kubectl logs sidecar-logging -c log-analyzer -f

# Check container status
kubectl get pod sidecar-logging -o jsonpath='{.status.containerStatuses[*].name}'
# Shows: app, log-shipper, log-analyzer

# Delete pod
kubectl delete pod sidecar-logging
```

### 3.3 Sidecar: Service Mesh Proxy (Envoy)

**sidecar-proxy.yaml**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-config
data:
  envoy.yaml: |
    static_resources:
      listeners:
      - name: listener_0
        address:
          socket_address:
            address: 0.0.0.0
            port_value: 8080
        filter_chains:
        - filters:
          - name: envoy.filters.network.http_connection_manager
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
              stat_prefix: ingress_http
              access_log:
              - name: envoy.access_loggers.stdout
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
              http_filters:
              - name: envoy.filters.http.router
              route_config:
                name: local_route
                virtual_hosts:
                - name: backend
                  domains: ["*"]
                  routes:
                  - match:
                      prefix: "/"
                    route:
                      cluster: local_app
      clusters:
      - name: local_app
        connect_timeout: 0.25s
        type: STRICT_DNS
        lb_policy: ROUND_ROBIN
        load_assignment:
          cluster_name: local_app
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  socket_address:
                    address: 127.0.0.1
                    port_value: 8000
---
apiVersion: v1
kind: Pod
metadata:
  name: app-with-proxy
spec:
  volumes:
  - name: envoy-config
    configMap:
      name: envoy-config
  
  containers:
  # Main application
  - name: app
    image: hashicorp/http-echo:0.2.3
    args:
    - -text="Hello from app"
    - -listen=:8000
    ports:
    - containerPort: 8000
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
  
  # Sidecar: Envoy proxy
  - name: envoy-proxy
    image: envoyproxy/envoy:v1.24-latest
    command:
    - envoy
    - -c
    - /etc/envoy/envoy.yaml
    ports:
    - containerPort: 8080
      name: proxy
    volumeMounts:
    - name: envoy-config
      mountPath: /etc/envoy
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
```

**🔍 Proxy Sidecar Architecture:**
```
External Request
│
├─► Port 8080 (Envoy Proxy Sidecar)
│   ├─ TLS termination
│   ├─ Metrics collection
│   ├─ Access logging
│   ├─ Rate limiting
│   └─ Load balancing
│
└─► Port 8000 (Main App via localhost)
    └─ App doesn't handle cross-cutting concerns
    
Both containers in same pod:
- Share network namespace (localhost)
- Share storage volumes
- Scheduled together
- Scaled together
```

```bash
# Create ConfigMap and Pod
kubectl apply -f sidecar-proxy.yaml

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/app-with-proxy --timeout=60s

# Test direct app access (from another pod)
kubectl run test --rm -i --tty --image=curlimages/curl -- sh
# Get pod IP first
POD_IP=$(kubectl get pod app-with-proxy -o jsonpath='{.status.podIP}')
# Access app directly
curl http://$POD_IP:8000
# Access via proxy
curl http://$POD_IP:8080
exit

# Port forward to test from your machine
kubectl port-forward pod/app-with-proxy 8080:8080 &

# Test
curl http://localhost:8080
# Response: Hello from app (proxied through Envoy)

# View Envoy access logs
kubectl logs app-with-proxy -c envoy-proxy

# View app logs
kubectl logs app-with-proxy -c app

# Clean up
pkill -f "kubectl port-forward"
kubectl delete pod app-with-proxy
kubectl delete configmap envoy-config
```

**💡 Sidecar Best Practices:**

```yaml
# ✅ GOOD: Use sidecars for
- Logging/monitoring (Fluentd, Prometheus exporters)
- Service mesh (Envoy, Linkerd)
- Security (Policy enforcement, cert management)
- Configuration management (Consul, Vault)

# ✅ GOOD: Share volumes between containers
volumes:
- name: shared-data
  emptyDir: {}

# ✅ GOOD: Set resource limits for sidecars
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

# ❌ BAD: Don't use sidecars for
- Unrelated services (use separate pods)
- Services that should scale independently
- Heavy processes (impacts main container)
```

---

## Part 4: Resource Management

**📚 Resource Types:**
- **CPU** - Measured in cores (1 = 1 CPU core)
  - `1` = 1 core, `0.5` = half core, `500m` = 500 millicores = 0.5 core
- **Memory** - Measured in bytes
  - `128Mi` = 128 mebibytes, `1Gi` = 1 gibibyte

**📚 Requests vs Limits:**
```
Requests:
├─ Guaranteed minimum resources
├─ Used by scheduler for placement
└─ Pod won't start if node doesn't have requested resources

Limits:
├─ Maximum resources allowed
├─ Enforced by kubelet via cgroups
├─ CPU: Throttled if exceeds limit
└─ Memory: OOMKilled if exceeds limit
```

### 4.1 Basic Resource Management

**resources-basic.yaml**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: resources-demo
spec:
  containers:
  - name: app
    image: nginx:latest
    
    resources:
      # Requests: Minimum guaranteed
      requests:
        cpu: 250m      # 0.25 CPU cores
        memory: 256Mi  # 256 mebibytes
      
      # Limits: Maximum allowed
      limits:
        cpu: 500m      # 0.5 CPU cores
        memory: 512Mi  # 512 mebibytes
```

**🔍 How Resource Management Works:**
```
Scheduler Decision:
Node has: 4 CPUs, 8Gi RAM
Current usage:
├─ CPU requests: 2.5 (from other pods)
├─ Memory requests: 4Gi (from other pods)

New pod requests: 250m CPU, 256Mi RAM
├─ Available CPU: 4 - 2.5 = 1.5 ✓ (250m fits)
├─ Available Memory: 8Gi - 4Gi = 4Gi ✓ (256Mi fits)
└─ Pod scheduled to this node

On the node (via cgroups):
├─ CPU: Guaranteed 250m, can burst up to 500m
└─ Memory: Guaranteed 256Mi, killed if exceeds 512Mi
```

```bash
# Create pod with resources
kubectl apply -f resources-basic.yaml

# Wait for pod
kubectl wait --for=condition=ready pod/resources-demo --timeout=60s

# Check resource usage
kubectl top pod resources-demo
# Shows actual CPU and memory usage

# Describe pod (shows requests/limits)
kubectl describe pod resources-demo | grep -A 10 "Requests:"

# View in JSON
kubectl get pod resources-demo -o json | jq '.spec.containers[0].resources'

# Stress test CPU (generate load)
kubectl exec resources-demo -- sh -c "while true; do echo; done" &
# CPU will be throttled at 500m limit

# Check metrics
kubectl top pod resources-demo
# CPU usage capped at ~500m

# Kill stress process
kubectl exec resources-demo -- pkill sh

# Delete pod
kubectl delete pod resources-demo
```

### 4.2 Quality of Service (QoS) Classes

**📚 QoS Classes:**

Kubernetes assigns QoS class based on resource requests/limits:

| QoS Class | Criteria | Eviction Priority |
|-----------|----------|-------------------|
| **Guaranteed** | limits = requests for all containers | Lowest (last to evict) |
| **Burstable** | Some requests set, limits > requests | Medium |
| **BestEffort** | No requests or limits set | Highest (first to evict) |

**qos-classes.yaml**
```yaml
# Guaranteed QoS
apiVersion: v1
kind: Pod
metadata:
  name: qos-guaranteed
spec:
  containers:
  - name: app
    image: nginx:latest
    resources:
      requests:
        cpu: 250m
        memory: 256Mi
      limits:
        cpu: 250m      # Same as request
        memory: 256Mi  # Same as request
---
# Burstable QoS
apiVersion: v1
kind: Pod
metadata:
  name: qos-burstable
spec:
  containers:
  - name: app
    image: nginx:latest
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m      # Higher than request
        memory: 512Mi  # Higher than request
---
# BestEffort QoS
apiVersion: v1
kind: Pod
metadata:
  name: qos-besteffort
spec:
  containers:
  - name: app
    image: nginx:latest
    # No resources specified
```

**🔍 QoS and Eviction:**
```
Node under memory pressure:
│
├─ Kill BestEffort pods first (no guarantees)
├─ Then kill Burstable pods exceeding requests
└─ Last resort: Kill Guaranteed pods

Example scenario:
Node has 4Gi memory, usage at 3.9Gi

Pods:
├─ qos-guaranteed (256Mi request) - Safe
├─ qos-burstable (128Mi request, 512Mi limit, using 400Mi) - At risk!
└─ qos-besteffort (no request, using 200Mi) - Will be killed first

Eviction order:
1. qos-besteffort (killed)
2. If still needed: qos-burstable (killed)
3. If still needed: qos-guaranteed (killed)
```

```bash
# Create all three QoS pods
kubectl apply -f qos-classes.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=nginx --timeout=60s

# Check QoS class assigned
kubectl get pod qos-guaranteed -o jsonpath='{.status.qosClass}'
# Returns: Guaranteed

kubectl get pod qos-burstable -o jsonpath='{.status.qosClass}'
# Returns: Burstable

kubectl get pod qos-besteffort -o jsonpath='{.status.qosClass}'
# Returns: BestEffort

# View all pods with QoS class
kubectl get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass

# Describe to see resource settings
kubectl describe pod qos-guaranteed | grep -A 5 "QoS Class:"

# Clean up
kubectl delete pod qos-guaranteed qos-burstable qos-besteffort
```

### 4.3 LimitRange - Default Resources

**📚 LimitRange:**
- Sets default requests/limits for namespace
- Enforces min/max per pod/container
- Applied automatically to pods without resource specs

**limitrange-demo.yaml**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: resource-constrained
---
apiVersion: v1
kind: LimitRange
metadata:
  name: resource-limits
  namespace: resource-constrained
spec:
  limits:
  # Container limits
  - type: Container
    default:          # Default limits (if not specified)
      cpu: 500m
      memory: 512Mi
    defaultRequest:   # Default requests (if not specified)
      cpu: 100m
      memory: 128Mi
    max:              # Maximum allowed
      cpu: 2
      memory: 2Gi
    min:              # Minimum required
      cpu: 50m
      memory: 64Mi
    maxLimitRequestRatio:  # Limit/Request ratio
      cpu: 4     # Limit can be max 4x request
      memory: 4  # Limit can be max 4x request
  
  # Pod limits (sum of all containers)
  - type: Pod
    max:
      cpu: 4
      memory: 4Gi
---
# Pod without resources (will get defaults)
apiVersion: v1
kind: Pod
metadata:
  name: default-resources
  namespace: resource-constrained
spec:
  containers:
  - name: app
    image: nginx:latest
    # No resources specified - defaults applied!
---
# Pod exceeding max (will be rejected)
apiVersion: v1
kind: Pod
metadata:
  name: too-big
  namespace: resource-constrained
spec:
  containers:
  - name: app
    image: nginx:latest
    resources:
      requests:
        cpu: 3  # Exceeds max of 2!
        memory: 3Gi
```

```bash
# Create namespace and LimitRange
kubectl apply -f limitrange-demo.yaml

# Check LimitRange
kubectl get limitrange -n resource-constrained
kubectl describe limitrange resource-limits -n resource-constrained

# View pod with defaults applied
kubectl get pod default-resources -n resource-constrained -o yaml | grep -A 10 "resources:"
# Shows: Default requests and limits applied automatically

# Try to create pod exceeding max (will fail)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: too-big
  namespace: resource-constrained
spec:
  containers:
  - name: app
    image: nginx:latest
    resources:
      requests:
        cpu: 3
        memory: 3Gi
EOF
# Error: exceeds max limit

# Clean up
kubectl delete namespace resource-constrained
```

### 4.4 ResourceQuota - Namespace Limits

**📚 ResourceQuota:**
- Limits total resources per namespace
- Prevents one team from consuming all cluster resources
- Enforced at namespace level

**resourcequota-demo.yaml**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-quota
  namespace: team-a
spec:
  hard:
    # Compute resources
    requests.cpu: "2"        # Total CPU requests: max 2 cores
    requests.memory: 4Gi     # Total memory requests: max 4Gi
    limits.cpu: "4"          # Total CPU limits: max 4 cores
    limits.memory: 8Gi       # Total memory limits: max 8Gi
    
    # Object counts
    pods: "10"               # Max 10 pods
    services: "5"            # Max 5 services
    persistentvolumeclaims: "3"  # Max 3 PVCs
    configmaps: "10"         # Max 10 ConfigMaps
    secrets: "10"            # Max 10 Secrets
```

```bash
# Create namespace and quota
kubectl apply -f resourcequota-demo.yaml

# View quota
kubectl get resourcequota -n team-a
kubectl describe resourcequota team-quota -n team-a
# Shows: Used / Hard for each resource

# Create pod (must have resource requests!)
kubectl run app1 -n team-a --image=nginx \
  --requests='cpu=500m,memory=1Gi' \
  --limits='cpu=1,memory=2Gi'

# Check quota usage
kubectl describe resourcequota team-quota -n team-a
# Shows: 500m/2 CPU requests, 1Gi/4Gi memory requests

# Create another pod
kubectl run app2 -n team-a --image=nginx \
  --requests='cpu=1,memory=2Gi' \
  --limits='cpu=2,memory=4Gi'

# Check quota again
kubectl describe resourcequota team-quota -n team-a
# Shows: 1.5/2 CPU requests, 3Gi/4Gi memory requests

# Try to exceed quota (will fail)
kubectl run app3 -n team-a --image=nginx \
  --requests='cpu=1,memory=2Gi'
# Error: exceeded quota

# Clean up
kubectl delete namespace team-a
```

**💡 Resource Management Best Practices:**

```yaml
# ✅ GOOD: Always set requests and limits
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

# ❌ BAD: No resources (BestEffort, first to be evicted)
# No resources section

# ✅ GOOD: Requests = Limits for critical apps (Guaranteed QoS)
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 500m
    memory: 512Mi

# ✅ GOOD: Use LimitRange for defaults
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: 100m
      memory: 128Mi

# ✅ GOOD: Use ResourceQuota per namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
```

---

## Complete Lab Cleanup

```bash
# Delete all resources
kubectl delete statefulset --all
kubectl delete daemonset --all
kubectl delete pod --all
kubectl delete service --all
kubectl delete configmap --all
kubectl delete secret --all
kubectl delete pvc --all
kubectl delete namespace resource-constrained team-a

# Verify cleanup
kubectl get all

# Stop Minikube (optional)
minikube stop
```

---

## Summary & Key Takeaways

### **StatefulSet**
- **Use for**: Databases, message queues, distributed systems
- **Features**: Stable names, persistent storage, ordered operations
- **Key**: Requires headless service, creates PVCs automatically

### **DaemonSet**
- **Use for**: Node-level agents (logging, monitoring, storage)
- **Features**: One pod per node, auto-scales with cluster
- **Key**: Use nodeSelector and tolerations for placement

### **Init Containers**
- **Use for**: Startup tasks, migrations, dependency checks
- **Features**: Run sequentially before main containers
- **Key**: Must succeed for main containers to start

### **Sidecar Containers**
- **Use for**: Logging, proxying, monitoring
- **Features**: Run alongside main container
- **Key**: Share network and storage with main container

### **Resource Management**
- **Requests**: Guaranteed minimum (used for scheduling)
- **Limits**: Maximum allowed (enforced by cgroups)
- **QoS Classes**: Guaranteed > Burstable > BestEffort
- **Best Practice**: Always set requests and limits

---

## Next Steps

1. **Practice** each workload type with real applications
2. **Experiment** with resource constraints and observe behavior
3. **Monitor** resource usage with `kubectl top`
4. **Learn** about Horizontal Pod Autoscaling (HPA)
5. **Explore** Vertical Pod Autoscaling (VPA)