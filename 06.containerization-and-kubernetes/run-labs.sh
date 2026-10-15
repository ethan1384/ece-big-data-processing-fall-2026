#!/usr/bin/env bash
# Exécute les labs 1, 2 et 3 du module 06 et enregistre toutes les sorties dans run-labs.log
# Usage (Git Bash, dans le dossier 06.containerization-and-kubernetes) :  bash run-labs.sh
# Prérequis : Docker Desktop lancé, minikube et kubectl installés.

cd "$(dirname "$0")"
LOG="$PWD/run-labs.log"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

step() { echo; echo "=================== $* ==================="; }
run()  { echo; echo "\$ $*"; eval "$@"; }

for bin in minikube kubectl curl jq; do
  command -v $bin >/dev/null || echo "!! $bin introuvable dans le PATH"
done

PF_PIDS=()
cleanup_pf() { for p in "${PF_PIDS[@]}"; do kill "$p" 2>/dev/null; done; PF_PIDS=(); }
trap cleanup_pf EXIT

# Expose un service sur localhost via port-forward (remplace le tunnel "minikube service --url")
forward() { # $1 = service, $2 = port local, $3 = namespace (optionnel)
  kubectl ${3:+-n $3} port-forward "svc/$1" "$2:8080" >/dev/null 2>&1 &
  PF_PIDS+=($!); sleep 4
}

########################################## LAB 1
step "LAB 1 - 1. minikube"
run minikube start
run minikube status
run kubectl get nodes
run kubectl describe node minikube
run minikube addons enable metrics-server
echo "(attente 90 s que metrics-server collecte des métriques)"; sleep 90
run kubectl top pods -A --sort-by cpu --sum=true
run kubectl -n kube-system get pods

step "LAB 1 - 2. kubectl"
run kubectl create deployment kubernetes-bootcamp --image=gcr.io/google-samples/kubernetes-bootcamp:v1
run kubectl rollout status deployments/kubernetes-bootcamp --timeout=180s
run kubectl get pods
POD_NAME=$(kubectl get pods -l app=kubernetes-bootcamp -o jsonpath='{.items[0].metadata.name}')
echo "POD_NAME=$POD_NAME"
run kubectl logs $POD_NAME
run kubectl describe pod $POD_NAME
run kubectl exec $POD_NAME -- cat /etc/os-release
run kubectl exec $POD_NAME -- ls /
run kubectl exec $POD_NAME -- cat /server.js
run kubectl exec $POD_NAME -- curl -s localhost:8080
echo; echo "Accès depuis l'hôte sans Service (IP du pod) :"
POD_IP=$(kubectl get pod $POD_NAME -o jsonpath='{.status.podIP}'); echo "POD_IP=$POD_IP"
run curl -s -m 5 "http://$POD_IP:8080" '||' echo "ECHEC: pod injoignable depuis la machine locale"

step "LAB 1 - 3. Service NodePort"
run kubectl expose deployments/kubernetes-bootcamp --type="NodePort" --port 8080
run kubectl get services
run minikube ip
forward kubernetes-bootcamp 18080
APP_URL="http://127.0.0.1:18080"; echo "APP_URL=$APP_URL"
run curl -s "$APP_URL"

step "LAB 1 - 4. Scale"
run kubectl scale deployments/kubernetes-bootcamp --replicas=5
run kubectl rollout status deployments/kubernetes-bootcamp --timeout=120s
run kubectl get pods
cleanup_pf; forward kubernetes-bootcamp 18080
echo "(port-forward cible 1 seul pod ; test de load balancing via le NodePort depuis le nœud minikube)"
NODEPORT=$(kubectl get svc kubernetes-bootcamp -o jsonpath='{.spec.ports[0].nodePort}')
run "minikube ssh -- 'for i in \$(seq 10); do curl -s localhost:$NODEPORT; done'"
run kubectl scale deployments/kubernetes-bootcamp --replicas=2
sleep 15
run kubectl get pods

step "LAB 1 - 5. Rolling update"
loop() { minikube ssh -- "for i in \$(seq $1); do curl -s -m 1 localhost:$NODEPORT; sleep 0.5; done" ; }
loop 60 > rollout-v2.txt 2>&1 &
LOOP=$!
sleep 3
run kubectl set image deployments/kubernetes-bootcamp kubernetes-bootcamp=jocatalin/kubernetes-bootcamp:v2
run kubectl rollout status deployments/kubernetes-bootcamp --timeout=180s
wait $LOOP; echo "--- réponses pendant la mise à jour v1 -> v2 :"; cat rollout-v2.txt; rm -f rollout-v2.txt
run kubectl set image deployments/kubernetes-bootcamp kubernetes-bootcamp=jocatalin/kubernetes-bootcamp:v3
sleep 40
run kubectl get pods
run kubectl rollout status deployments/kubernetes-bootcamp --timeout=10s
echo "--- le service répond-il encore ?"; loop 6
run kubectl rollout undo deployments/kubernetes-bootcamp
run kubectl rollout status deployments/kubernetes-bootcamp --timeout=120s
run kubectl rollout history deployments/kubernetes-bootcamp
run kubectl rollout history deployments/kubernetes-bootcamp --revision=1
run kubectl rollout undo deployments/kubernetes-bootcamp --to-revision=1
run kubectl rollout status deployments/kubernetes-bootcamp --timeout=120s
loop 4

step "LAB 1 - 6. Manifests"
cleanup_pf
run kubectl delete service kubernetes-bootcamp
run kubectl delete deployment kubernetes-bootcamp
cd lab-1
echo "--- étape 4 : deployment sans replicas (1 pod par défaut)"
grep -v "replicas:" deployment.yaml > /tmp/deploy-1replica.yaml
run kubectl apply -f /tmp/deploy-1replica.yaml
run kubectl rollout status deployment/kubernetes-bootcamp --timeout=120s
run kubectl get pods
run kubectl apply -f service.yaml
run kubectl get svc kubernetes-bootcamp-service
NODEPORT=$(kubectl get svc kubernetes-bootcamp-service -o jsonpath='{.spec.ports[0].nodePort}')
run "minikube ssh -- 'curl -s localhost:$NODEPORT'"
echo "--- étape 8 : replicas: 3"
run kubectl apply -f deployment.yaml
run kubectl rollout status deployment/kubernetes-bootcamp --timeout=120s
run kubectl get pods
run "minikube ssh -- 'for i in \$(seq 10); do curl -s localhost:$NODEPORT; done'"
step "LAB 1 - 7. Teardown (sans minikube stop, labs 2-3 suivent)"
run kubectl delete -f service.yaml
run kubectl delete -f deployment.yaml
cd ..

########################################## LAB 2
step "LAB 2 - ConfigMap & Secret"
NS=lab-configmap-secret
run kubectl create namespace $NS
mkdir -p lab-configmap-secret && cd lab-configmap-secret
cat > pipeline-config.properties << 'EOF'
# Data Pipeline Configuration
bronze.path=/mnt/data/bronze
silver.path=/mnt/data/silver
gold.path=/mnt/data/gold
batch.size=1000
retention.days=90
log.level=INFO
spark.cores=4
kafka.brokers=kafka-0.kafka.svc.cluster.local:9092
EOF
run kubectl -n $NS create configmap pipeline-config --from-file=pipeline-config.properties
run kubectl -n $NS describe configmap pipeline-config
run kubectl -n $NS create configmap data-paths --from-literal=bronze=/mnt/data/bronze --from-literal=silver=/mnt/data/silver --from-literal=gold=/mnt/data/gold
run kubectl -n $NS get configmap data-paths -o yaml
cat > configmap-data-platform.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: data-platform-config
  namespace: lab-configmap-secret
data:
  log_level: INFO
  spark_workers: "4"
  batch_size: "1000"
  application.yaml: |
    pipeline:
      name: bronze-to-silver-etl
      schedule: "0 2 * * *"
      timeout_minutes: 120
    storage:
      type: s3
      endpoint: ceph-rgw.ceph-storage.svc.cluster.local:7480
      region: us-east-1
    kafka:
      bootstrap_servers: kafka-0.kafka.svc.cluster.local:9092
      consumer_group: data-platform-consumers
      topic_prefix: data.bronze
  table_mappings.csv: |
    source_table,bronze_path,silver_layer
    customers,/data/bronze/customers,deduplicated_customers
    orders,/data/bronze/orders,aggregated_orders
    products,/data/bronze/products,product_catalog
EOF
run kubectl apply -f configmap-data-platform.yaml
run "kubectl -n $NS get configmap data-platform-config -o jsonpath='{.data.log_level}'"; echo
run "kubectl -n $NS get configmap data-platform-config -o jsonpath='{.data.application\.yaml}'"
run kubectl -n $NS create secret generic ceph-credentials --from-literal=access-key=AKIAIOSFODNN7EXAMPLE --from-literal=secret-key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
run kubectl -n $NS get secret ceph-credentials -o yaml
printf '[default]\naws_access_key_id = AKIAIOSFODNN7EXAMPLE\naws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY\n' > s3-credentials.txt
run kubectl -n $NS create secret generic s3-credentials --from-file=s3-credentials.txt
cat > secret-ceph-credentials.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: ceph-s3-credentials
  namespace: lab-configmap-secret
type: Opaque
stringData:
  access-key: AKIAIOSFODNN7EXAMPLE
  secret-key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  endpoint: ceph-rgw.ceph-storage.svc.cluster.local:7480
  bucket: data-platform-bronze
EOF
run kubectl apply -f secret-ceph-credentials.yaml
run kubectl -n $NS get secret ceph-s3-credentials -o yaml
run "kubectl -n $NS get secret ceph-s3-credentials -o jsonpath='{.data.secret-key}' | base64 -d"; echo
run "kubectl -n $NS get secret ceph-s3-credentials -o json | jq -r '.data | to_entries[] | \"\(.key)=\(.value | @base64d)\"'"
cat > pods.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata: {name: spark-app, namespace: lab-configmap-secret}
spec:
  containers:
  - name: app
    image: busybox:1.37
    command: ["sleep", "600"]
    env:
    - name: LOG_LEVEL
      valueFrom: {configMapKeyRef: {name: data-platform-config, key: log_level}}
    - name: SPARK_WORKERS
      valueFrom: {configMapKeyRef: {name: data-platform-config, key: spark_workers}}
    envFrom:
    - configMapRef: {name: data-platform-config}
---
apiVersion: v1
kind: Pod
metadata: {name: ceph-connector, namespace: lab-configmap-secret}
spec:
  restartPolicy: Never
  containers:
  - name: ceph-app
    image: busybox:1.37
    command: ["sh", "-c", "echo \"Access Key: $S3_ACCESS_KEY\""]
    env:
    - name: S3_ACCESS_KEY
      valueFrom: {secretKeyRef: {name: ceph-s3-credentials, key: access-key}}
    envFrom:
    - secretRef: {name: ceph-s3-credentials}
---
apiVersion: v1
kind: Pod
metadata: {name: spark-config-reader, namespace: lab-configmap-secret}
spec:
  containers:
  - name: app
    image: busybox:1.37
    command: ["sleep", "600"]
    volumeMounts: [{name: config-volume, mountPath: /etc/config}]
  volumes:
  - name: config-volume
    configMap:
      name: data-platform-config
      items:
      - {key: application.yaml, path: application.yaml}
      - {key: table_mappings.csv, path: tables.csv}
---
apiVersion: v1
kind: Pod
metadata: {name: ceph-connector-secure, namespace: lab-configmap-secret}
spec:
  containers:
  - name: ceph-app
    image: busybox:1.37
    command: ["sh", "-c", "sleep 1000"]
    volumeMounts: [{name: ceph-creds, mountPath: /etc/ceph-credentials, readOnly: true}]
  volumes:
  - name: ceph-creds
    secret: {secretName: s3-credentials, defaultMode: 0600}
EOF
run kubectl apply -f pods.yaml
run kubectl -n $NS wait --for=condition=Ready pod/spark-app pod/spark-config-reader pod/ceph-connector-secure --timeout=180s
run "kubectl -n $NS exec spark-app -- env | grep -iE 'log_level|spark'"
run "kubectl -n $NS wait --for=jsonpath='{.status.phase}'=Succeeded pod/ceph-connector --timeout=60s"
run kubectl -n $NS logs ceph-connector
run kubectl -n $NS exec spark-config-reader -- ls -la /etc/config/
run kubectl -n $NS exec spark-config-reader -- cat /etc/config/tables.csv
run kubectl -n $NS exec ceph-connector-secure -- ls -laL /etc/ceph-credentials/
cd ..
run kubectl delete namespace $NS
rm -rf lab-configmap-secret

########################################## LAB 3
step "LAB 3 - Job & CronJob"
NS=lab-job-cronjob
run minikube image pull python:3.13-slim
run kubectl create namespace $NS
mkdir -p lab-job-cronjob && cd lab-job-cronjob
job_retry() { cat << EOF
apiVersion: batch/v1
kind: Job
metadata: {name: data-transform-job, namespace: lab-job-cronjob}
spec:
  backoffLimit: 3
  activeDeadlineSeconds: $1
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: transform
        image: python:3.13-slim
        command: ["python", "-c", "import sys; print('Transforming records...'); print('ERROR: Validation failed!'); sys.exit(1)"]
EOF
}
cat > job-simple.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: data-import-job, namespace: lab-job-cronjob}
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: import
        image: python:3.13-slim
        command: ["python", "-c", "import time; print('Starting data import...'); time.sleep(3); print('Processing 1000 records...'); print('Import completed!')"]
EOF
run kubectl apply -f job-simple.yaml
run kubectl -n $NS wait --for=condition=complete job/data-import-job --timeout=60s
run kubectl -n $NS get job
run kubectl -n $NS logs -l job-name=data-import-job

echo "--- Job avec retry (activeDeadlineSeconds=300)"
job_retry 300 > job-with-retry.yaml
run kubectl apply -f job-with-retry.yaml
run kubectl -n $NS wait --for=condition=failed job/data-transform-job --timeout=240s
run kubectl -n $NS get pods -l job-name=data-transform-job
run kubectl -n $NS describe job data-transform-job
run kubectl -n $NS delete job data-transform-job
echo "--- Job avec retry (activeDeadlineSeconds=10)"
job_retry 10 > job-with-retry.yaml
run kubectl apply -f job-with-retry.yaml
run kubectl -n $NS wait --for=condition=failed job/data-transform-job --timeout=60s
run kubectl -n $NS get pods -l job-name=data-transform-job
run kubectl -n $NS describe job data-transform-job

echo "--- Job parallèle"
cat > job-parallel.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: batch-export-job, namespace: lab-job-cronjob}
spec:
  parallelism: 4
  completions: 4
  completionMode: Indexed
  backoffLimit: 2
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: export
        image: python:3.13-slim
        command: ["python", "-c"]
        args:
          - |
            import os, time
            pod = os.getenv('HOSTNAME', 'unknown')
            shard = int(os.environ['JOB_COMPLETION_INDEX'])
            print(f"Pod {pod}: Exporting shard {shard} (users with id % 4 == {shard})...")
            time.sleep(5)
            print(f"Pod {pod}: Shard {shard} export completed!")
EOF
run kubectl apply -f job-parallel.yaml
sleep 3; run kubectl -n $NS get pods -l job-name=batch-export-job -o wide
run kubectl -n $NS wait --for=condition=complete job/batch-export-job --timeout=90s
run kubectl -n $NS get job batch-export-job
run kubectl -n $NS logs -l job-name=batch-export-job --prefix

echo "--- CronJob toutes les 2 min (attente ~4 min 30)"
cat > cronjob-pipeline.yaml << 'EOF'
apiVersion: batch/v1
kind: CronJob
metadata: {name: bronze-to-silver-pipeline, namespace: lab-job-cronjob}
spec:
  schedule: "*/2 * * * *"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: transform
            image: python:3.13-slim
            command: ["python", "-c", "from datetime import datetime; import time; print(f'[{datetime.now()}] Bronze->Silver ETL started...'); time.sleep(2); print(f'[{datetime.now()}] Completed! 500 records processed')"]
EOF
run kubectl apply -f cronjob-pipeline.yaml
sleep 270
run kubectl -n $NS get cronjob
run kubectl -n $NS get jobs
J=$(kubectl -n $NS get jobs -o name | grep bronze-to-silver | head -1)
run kubectl -n $NS logs $J
run "kubectl -n $NS patch cronjob bronze-to-silver-pipeline -p '{\"spec\":{\"suspend\":true}}'"
run kubectl -n $NS get cronjob

echo "--- Scénario pipeline"
run kubectl -n $NS create configmap etl-config --from-literal=BATCH_SIZE=1000 --from-literal=SOURCE_LAYER=bronze --from-literal=TARGET_LAYER=silver
cat > cronjob-etl.yaml << 'EOF'
apiVersion: batch/v1
kind: CronJob
metadata: {name: etl-bronze-to-silver, namespace: lab-job-cronjob}
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 2
      ttlSecondsAfterFinished: 3600
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: etl
            image: python:3.13-slim
            envFrom: [{configMapRef: {name: etl-config}}]
            resources:
              requests: {cpu: 100m, memory: 64Mi}
              limits: {memory: 128Mi}
            command: ["python", "-c"]
            args:
              - |
                from datetime import datetime
                import os
                t = datetime.now().isoformat()
                s, d = os.environ['SOURCE_LAYER'], os.environ['TARGET_LAYER']
                print(f"[{t}] ETL: {s} -> {d}")
                print(f"[{t}] Batch size: {os.environ['BATCH_SIZE']}")
                print(f"[{t}] Reading, validating, deduplicating...")
                print(f"[{t}] Writing to {d} layer...")
                print(f"[{t}] Completed!")
EOF
run kubectl apply -f cronjob-etl.yaml
run kubectl -n $NS create job etl-manual-run --from=cronjob/etl-bronze-to-silver
run kubectl -n $NS wait --for=condition=complete job/etl-manual-run --timeout=60s
run kubectl -n $NS logs job/etl-manual-run
cd ..
run kubectl delete namespace $NS
run kubectl get namespace $NS
rm -rf lab-job-cronjob

step "FIN"
run minikube stop
echo "Log complet : $LOG"
