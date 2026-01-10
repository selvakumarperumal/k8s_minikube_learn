# Storage Examples

This folder contains comprehensive YAML examples for each storage topic.

## File Overview

| File | Topic | Examples |
|------|-------|----------|
| [01-volumes-examples.yaml](01-volumes-examples.yaml) | Volumes | emptyDir, hostPath, configMap, secret, projected |
| [02-pv-pvc-examples.yaml](02-pv-pvc-examples.yaml) | PV & PVC | Static provisioning, access modes, reclaim policies |
| [03-storageclass-examples.yaml](03-storageclass-examples.yaml) | StorageClasses | Dynamic provisioning, AWS/GCP/Azure examples |
| [04-statefulset-storage.yaml](04-statefulset-storage.yaml) | StatefulSet | PostgreSQL, Redis, multi-volume configurations |

## Quick Start

```bash
# 1. Volumes (works on any cluster)
kubectl apply -f 01-volumes-examples.yaml

# 2. PV/PVC examples
kubectl apply -f 02-pv-pvc-examples.yaml

# 3. StorageClass examples
kubectl apply -f 03-storageclass-examples.yaml

# 4. StatefulSet with storage
kubectl apply -f 04-statefulset-storage.yaml
```

## How to Use Each File

### 1. Volumes Examples

```bash
# Apply
kubectl apply -f 01-volumes-examples.yaml

# Test emptyDir sharing
kubectl logs emptydir-demo -c reader -f

# Test hostPath
kubectl exec hostpath-demo -- ls -la /host-logs/

# Test configMap volume
kubectl exec configmap-volume-demo -- cat /etc/config/database.conf

# Test secret volume
kubectl exec secret-volume-demo -- cat /etc/secrets/db-password

# Test projected volume
kubectl exec projected-volume-demo -- ls -la /etc/all/
```

### 2. PV/PVC Examples

```bash
# Apply
kubectl apply -f 02-pv-pvc-examples.yaml

# Check binding
kubectl get pv,pvc

# Test persistence
kubectl exec basic-pv-pod -- sh -c 'echo "Hello!" > /usr/share/nginx/html/test.txt'
kubectl exec basic-pv-pod -- cat /usr/share/nginx/html/test.txt

# Delete pod and recreate - data persists!
kubectl delete pod basic-pv-pod
kubectl apply -f 02-pv-pvc-examples.yaml
kubectl exec basic-pv-pod -- cat /usr/share/nginx/html/test.txt
```

### 3. StorageClass Examples

```bash
# View default StorageClass
kubectl get storageclass

# Apply custom StorageClasses
kubectl apply -f 03-storageclass-examples.yaml

# Test dynamic provisioning (no PV needed!)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-test
spec:
  storageClassName: basic-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Check - PV auto-created!
kubectl get pv,pvc
```

### 4. StatefulSet Storage Examples

```bash
# Apply
kubectl apply -f 04-statefulset-storage.yaml

# Wait for pods
kubectl wait --for=condition=ready pod --all --timeout=120s

# Check PostgreSQL persistence
kubectl exec -it postgres-0 -- psql -U postgres -c "CREATE TABLE test (id INT);"
kubectl delete pod postgres-0
kubectl wait --for=condition=ready pod/postgres-0 --timeout=120s
kubectl exec -it postgres-0 -- psql -U postgres -c "SELECT * FROM test;"

# Check Redis persistence
kubectl exec redis-0 -- redis-cli SET key value
kubectl delete pod redis-0
kubectl wait --for=condition=ready pod/redis-0 --timeout=60s
kubectl exec redis-0 -- redis-cli GET key
```

## Cleanup

```bash
# Delete all examples
kubectl delete -f 01-volumes-examples.yaml
kubectl delete -f 02-pv-pvc-examples.yaml
kubectl delete -f 03-storageclass-examples.yaml
kubectl delete -f 04-statefulset-storage.yaml

# Delete ConfigMaps and Secrets
kubectl delete configmap app-config nginx-custom-config redis-config
kubectl delete secret app-secrets postgres-secret

# Delete remaining PVCs (StatefulSet PVCs persist!)
kubectl delete pvc --all

# Delete remaining PVs (with Retain policy)
kubectl delete pv --all
```

## Common Patterns

### Pattern 1: Temp Storage (emptyDir)
```yaml
volumes:
  - name: cache
    emptyDir:
      sizeLimit: 100Mi
```

### Pattern 2: Persistent Storage (PVC)
```yaml
volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-pvc
```

### Pattern 3: Config from ConfigMap
```yaml
volumes:
  - name: config
    configMap:
      name: app-config
```

### Pattern 4: Secrets as Files
```yaml
volumes:
  - name: secrets
    secret:
      secretName: app-secrets
      defaultMode: 0400
```

### Pattern 5: StatefulSet with Storage
```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```
