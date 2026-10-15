# Module 06 answers

I ran the three labs on October 15, 2026 with minikube v1.39.0 (Kubernetes v1.34.1, Docker driver) on Ubuntu in WSL 2, using a dedicated profile called ece-module06. The command outputs are in [execution-06](./execution-06/) and the manifests I applied are in [execution-06/manifests](./execution-06/manifests/).

## Lab 1: Kubernetes basics with minikube

### 1. Install minikube

The node ece-module06 came up Ready. Right after enabling metrics-server the first kubectl top call said the metrics API was not available yet, the second one worked.

kubectl top pods -A --sort-by cpu --sum=true shows the CPU and memory used by every pod in all namespaces (-A), sorted by CPU, with a total line at the bottom (--sum). On my cluster kube-apiserver was the biggest consumer by far (about 109m CPU and 187Mi), then etcd and the controller manager.

In kube-system I found kube-apiserver (the entry point that kubectl talks to), etcd (the key-value store holding the cluster state), kube-scheduler (picks a node for new pods), kube-controller-manager (runs the control loops that keep the actual state equal to the desired one, like the number of replicas), kube-proxy (writes the network rules behind Services), coredns (DNS names for Services), kindnet (the CNI plugin for pod networking), storage-provisioner (minikube's provisioner for PVCs) and metrics-server. The kubelet and containerd run directly on the node, so I think that is why they don't show up as pods.

### 2. kubectl commands

The first pod was kubernetes-bootcamp-658f6cbd58-ltjmd with IP 10.244.0.12. The image runs Debian 8 (jessie). The source code is /server.js at the root of the container and it listens on port 8080, so curl localhost:8080 inside the pod returned "Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-658f6cbd58-ltjmd | v=1".

From my machine I could not reach the app: curl on 10.244.0.12:8080 timed out. The pod IP only exists on the cluster network, nothing exposes it outside yet.

### 3. Expose the service

I exposed it with kubectl expose deployments/kubernetes-bootcamp --type="NodePort" --port 8080 and the Service got NodePort 31576, the node IP was 192.168.49.2. With the Docker driver under WSL that IP is not reachable from the host, so I used kubectl port-forward svc/kubernetes-bootcamp 18080:8080 and curl on http://127.0.0.1:18080 answered with v=1.

### 4. Scale up and down

After scaling to 5 replicas I checked with kubectl get pods, all 5 pods were Running and 1/1. When I queried the service 20 times the pod name in the response changed, I saw 3 different pods. The Service load balances each new connection across the pods matching app=kubernetes-bootcamp, and since kube-proxy picks randomly it's probably normal that not all 5 showed up in only 20 requests. I sent these requests to the NodePort from inside the minikube node, because port-forward attaches to a single pod and would always show the same name. Then I scaled down to 2 and kubectl get pods showed only 2 pods left.

### 5. Rolling update and rollback

During the update to jocatalin/kubernetes-bootcamp:v2 I had a loop of 80 requests running: 8 answered v=1 and 72 answered v=2, and none failed. So the service was not interrupted, Kubernetes starts new pods and only removes the old ones once the new ones are ready.

With the v3 tag the new pod went to ErrImagePull then ImagePullBackOff because the image doesn't exist, and the rollout stayed stuck. The service still answered v=2, because the deployment only replaces an old pod once a new one is ready, so the two v2 pods were never removed.

kubectl rollout undo brought back v2. After that the history showed revisions 1, 3 and 4 (revision 2 became revision 4 when it was restored), so I went back to the original image with kubectl rollout undo deployments/kubernetes-bootcamp --to-revision=1, and the responses were v=1 again.

### 6. Deploy with manifest files

In [deployment.yaml](./lab-1/deployment.yaml) I added the image gcr.io/google-samples/kubernetes-bootcamp:v1 with containerPort 8080, and replicas: 3 for the last step. In [service.yaml](./lab-1/service.yaml) the selector is app: kubernetes-bootcamp and the port is 8080, targetPort defaults to the same value.

I first applied the deployment without replicas and got one running pod. Right after applying the service the first curl on the new NodePort (32726) was refused, I think kube-proxy had not written the rules yet, and a few seconds later it answered normally. With replicas: 3 the three pods were ready and 40 requests were spread over all of them (14, 9 and 17).

### 7. Teardown

I deleted the service and the deployment. I kept minikube running for labs 2 and 3 and stopped it at the end of lab 3.

## Lab 2: ConfigMap and Secret

The three ways to create a ConfigMap worked. With --from-file the whole properties file is stored under a single key named after the file, with --from-literal each pair becomes its own key, and the YAML manifest mixes simple keys and full files. Values in data have to be strings, which is why "4" and "1000" are quoted. To read the application.yaml key with JSONPath the dot has to be escaped.

The three ways to create a Secret also worked. In the output the values are base64 encoded and decoding them gives back the example keys from the lab, so it's only an encoding, not encryption. With stringData I can write the values in clear and the API server encodes them. I didn't have jq so I decoded all the fields with a small Python one-liner instead.

In spark-app the variables LOG_LEVEL=INFO and SPARK_WORKERS=4 were there, plus the lowercase keys like log_level and spark_workers coming from envFrom. ceph-connector printed the access key and ended in Completed, which shows that a Secret injected as an env var is readable by anything in the container and can easily end up in the logs.

The ConfigMap volume contained application.yaml and tables.csv, so the items list really selects and renames keys. The Secret volume was mounted read only and s3-credentials.txt had the permissions -rw------- (0600).

I think env vars are fine for small settings but they are fixed when the pod starts, while a mounted volume can give whole files and gets updated when the ConfigMap or Secret changes. In both cases base64 doesn't protect anything, so access to Secrets has to be restricted. In the manifests and logs committed here I replaced the example keys with placeholders.

## Lab 3: Job and CronJob

### Simple Job

data-import-job finished with 1/1 completions and the logs showed the three messages up to "Import completed!".

### Job with retry

How many pods were created and why are they kept? 4 pods, the first attempt plus 3 retries since backoffLimit is 3. With restartPolicy: Never each retry is a new pod instead of restarting the container. The failed pods are kept so that I can still read their logs and see why it failed, they go away only when the Job is deleted.

What is the reason of the failure? describe job shows BackoffLimitExceeded, the Job reached the maximum number of retries.

With activeDeadlineSeconds set to 10 the reason became DeadlineExceeded. Only 1 pod was created this time because the back-off delay before the next retry was longer than what was left of the 10 seconds, so the deadline killed the Job before it could use its retries.

### Parallel Job

batch-export-job ran 4 pods at the same time and finished 4/4. The logs had shards 0, 1, 2 and 3, each pod reads its index from JOB_COMPLETION_INDEX. ttlSecondsAfterFinished: 600 would delete the Job and its pods 10 minutes after the end, but I removed them before with the teardown.

### CronJob

With "*/2 * * * *" the CronJob created bronze-to-silver-pipeline-29867874 by itself and it completed with "Completed! 500 records processed". concurrencyPolicy: Forbid prevents two runs from overlapping, and the history limits keep the last 3 successful jobs and the last failed one.

daily-backup is scheduled at 2 AM Paris time thanks to timeZone. I didn't wait until 2 AM, I created a job from it with kubectl create job --from=cronjob/daily-backup and it printed "Backup completed". I also suspended and resumed bronze-to-silver-pipeline with the patch commands and checked the suspend field after each one.

### Data pipeline scenario

etl-manual-run, created from etl-bronze-to-silver, read its settings from the etl-config ConfigMap through envFrom and logged bronze to silver with a batch size of 1000 before "Completed!". The requests (100m CPU, 64Mi) are used by the scheduler to place the pod, and if the container goes over the 128Mi memory limit it would probably get OOMKilled.

At the end I deleted the namespace, kubectl get namespace lab-job-cronjob returned NotFound, and I stopped minikube.
