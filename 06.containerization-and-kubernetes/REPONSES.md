# Module 06 — Réponses aux labs

Les labs ont été exécutés le 15 octobre 2026 sur le cluster local `ece-module06`, avec Docker et minikube sous Ubuntu/WSL. Les sorties des commandes sont dans le dossier [execution-06](./execution-06/COMPTE_RENDU_EXECUTION.md).

## Lab 1 — Kubernetes avec minikube

### 1. Démarrage du cluster

Le nœud `ece-module06` est passé à l'état `Ready`. Après l'activation de metrics-server, il a fallu attendre un peu avant que les métriques soient disponibles.

La commande `kubectl top pods -A --sort-by cpu --sum=true` affiche la consommation CPU et mémoire des pods. `-A` permet de voir tous les namespaces, `--sort-by cpu` les classe par consommation CPU et `--sum=true` ajoute le total.

Dans `kube-system`, les principaux composants sont :

- `kube-apiserver` : reçoit les requêtes envoyées par `kubectl`.
- `etcd` : conserve l'état du cluster.
- `kube-scheduler` : choisit le nœud sur lequel placer les nouveaux pods.
- `kube-controller-manager` : fait respecter l'état demandé, par exemple le nombre de réplicas.
- `kube-proxy` : met en place les règles réseau des Services.
- `coredns` : permet de retrouver les Services par leur nom.
- `kindnet` : assure le réseau des pods dans ce cluster.
- `storage-provisioner` : fournit le stockage demandé par les PVC.
- `metrics-server` : récupère les mesures CPU et mémoire utilisées par `kubectl top`.

Le kubelet et le runtime des conteneurs tournent directement sur le nœud ; ils ne sont donc pas dans cette liste de pods.

### 2. Application bootcamp

Le premier pod était `kubernetes-bootcamp-658f6cbd58-ltjmd`, avec l'IP `10.244.0.12`. Les logs montrent le démarrage de l'application. L'image utilise Debian 8 (jessie).

Le code est dans `/server.js`, à la racine du conteneur. Le serveur écoute sur le port `8080`. Depuis le pod, `curl localhost:8080` renvoie :

```text
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-658f6cbd58-ltjmd | v=1
```

Depuis l'hôte, l'accès direct à `10.244.0.12:8080` a échoué avec un timeout. Dans cette installation, l'IP du pod n'est pas accessible directement depuis Ubuntu/WSL.

### 3. Exposition du Service

Le Deployment a été exposé avec :

```bash
kubectl expose deployment/kubernetes-bootcamp --type=NodePort --port=8080
```

Le Service a reçu le NodePort `31576`, pour le port `8080` de l'application. L'IP du nœud était `192.168.49.2`. Pour accéder à l'application depuis l'hôte, un tunnel a été ouvert :

```bash
kubectl port-forward svc/kubernetes-bootcamp 18080:8080
curl http://127.0.0.1:18080
```

La réponse contenait bien `v=1`.

### 4. Augmentation et réduction du nombre de pods

Après `kubectl scale deployment/kubernetes-bootcamp --replicas=5`, la commande `kubectl get pods` montrait cinq pods `Running` et prêts (`1/1`).

Sur les requêtes suivantes, le nom du pod dans la réponse changeait. Le Service répartit les nouvelles connexions entre les pods sélectionnés par le label `app=kubernetes-bootcamp`. Trois noms de pods différents ont été observés sur les vingt requêtes envoyées.

Pour cette vérification, les requêtes ont été envoyées au NodePort depuis le nœud minikube. Le tunnel `port-forward` utilisé juste avant cible un seul pod et ne permet pas d'observer cette répartition.

Après le passage à `--replicas=2`, trois pods ont été supprimés et il en restait bien deux.

### 5. Mise à jour et retour en arrière

Pendant la mise à jour vers `jocatalin/kubernetes-bootcamp:v2`, les réponses sont passées de `v=1` à `v=2`. Aucune erreur HTTP n'a été observée sur les 80 requêtes de suivi. Kubernetes remplace progressivement les anciens pods par les nouveaux.

Avec l'image `v3`, le nouveau pod n'a pas pu démarrer, car ce tag n'existe pas. Le téléchargement de l'image a échoué et le rollout est resté bloqué. Les deux pods `v2` étaient toujours disponibles, donc le Service continuait à répondre en `v=2`.

La commande suivante a annulé cette mise à jour :

```bash
kubectl rollout undo deployment/kubernetes-bootcamp
```

L'historique montrait ensuite les révisions 1, 3 et 4. La révision 1 correspondait à l'image initiale ; le retour à cette version s'est fait avec :

```bash
kubectl rollout undo deployment/kubernetes-bootcamp --to-revision=1
```

Les réponses contenaient de nouveau `v=1`.

### 6. Déploiement avec les fichiers YAML

Dans [deployment.yaml](./lab-1/deployment.yaml), les champs à compléter sont l'image `gcr.io/google-samples/kubernetes-bootcamp:v1`, le port `8080` et, pour la dernière étape, `replicas: 3`.

Dans [service.yaml](./lab-1/service.yaml), le sélecteur est `app: kubernetes-bootcamp` et le port est `8080`. Comme `targetPort` n'est pas précisé, il prend la même valeur que `port`.

Le Deployment a d'abord été appliqué sans `replicas`, ce qui a créé un pod. Après application du Service, la première connexion a été refusée juste après sa création. Une fois les règles réseau en place, l'application répondait correctement.

Le fichier avec `replicas: 3` a ensuite été appliqué. Les trois pods étaient prêts et les requêtes ont été servies par chacun d'eux.

### 7. Nettoyage

Le Service et le Deployment ont été supprimés. Le cluster a été gardé pour les labs suivants, puis arrêté à la fin du Lab 3.

## Lab 2 — ConfigMap et Secret

Les trois méthodes de création des ConfigMaps ont fonctionné. Avec `--from-file`, le fichier properties est stocké sous une seule clé. Avec `--from-literal`, chaque valeur devient une clé séparée. Le manifest YAML permet de regrouper les paramètres et les fichiers de configuration.

Les valeurs de `data` doivent être des chaînes, d'où les guillemets autour de `"4"` et `"1000"`. Pour récupérer la clé `application.yaml` avec JSONPath, il faut échapper le point : `{.data.application\.yaml}`.

Les Secrets ont aussi été créés à partir de valeurs littérales, d'un fichier et d'un manifest. Les valeurs de `data` sont encodées en base64. Leur décodage a permis de retrouver les valeurs d'exemple de l'énoncé : ce n'est donc pas du chiffrement. `stringData` permet de fournir directement les valeurs en clair à l'API.

Dans `spark-app`, les variables `LOG_LEVEL=INFO` et `SPARK_WORKERS=4` étaient bien présentes. Les clés ajoutées par `envFrom`, comme `log_level` et `spark_workers`, apparaissaient également.

Le pod `ceph-connector` a affiché la clé d'accès d'exemple, puis s'est terminé en `Completed`. Cela montre qu'un Secret injecté dans l'environnement est lisible dans le conteneur et peut aussi se retrouver dans ses logs.

Le volume ConfigMap contenait `application.yaml` et `tables.csv`. La clé `table_mappings.csv` a donc bien été montée sous le nom `tables.csv`.

Pour le volume Secret, le fichier `s3-credentials.txt` était monté en lecture seule avec les permissions `-rw-------`, soit `0600`. Son contenu a pu être lu depuis le conteneur.

Les variables d'environnement conviennent aux paramètres simples, mais elles restent fixées au démarrage du pod. Un volume permet de fournir des fichiers et peut recevoir les mises à jour de la ConfigMap ou du Secret. Les accès aux Secrets doivent être limités ; leur encodage base64 ne suffit pas à les protéger.

Le namespace `lab-configmap-secret` a été supprimé à la fin.

## Lab 3 — Job et CronJob

### Job simple

Le Job `data-import-job` s'est terminé avec une complétion sur une attendue (`1/1`). Ses logs affichaient le début de l'import, le message sur les 1000 enregistrements et `Import completed!`. Le script de l'énoncé simule cet import avec des messages ; il ne lit pas de données externes.

### Job avec nouvelles tentatives

**Combien de pods ont été créés et pourquoi sont-ils conservés ?**

Quatre pods ont été créés : une première tentative et trois nouvelles tentatives avec `backoffLimit: 3`. Ils ont tous échoué. Avec `restartPolicy: Never`, Kubernetes crée un nouveau pod au lieu de redémarrer le conteneur dans le même pod. Les pods échoués restent disponibles pour consulter leurs logs.

**Quelle est la raison de l'échec du Job ?**

La sortie de `kubectl describe job` indiquait `BackoffLimitExceeded` : le nombre de nouvelles tentatives autorisées avait été atteint.

**Que se passe-t-il avec `activeDeadlineSeconds: 10` ?**

Après suppression et recréation du Job, la raison était `DeadlineExceeded`. Un seul pod a été créé pendant cette exécution. La limite de temps a été atteinte avant que le Job puisse effectuer toutes les nouvelles tentatives.

### Parallélisation

Le Job `batch-export-job` a lancé quatre pods en parallèle et s'est terminé avec `4/4` complétions. Les logs contenaient les indices 0, 1, 2 et 3 : chaque pod récupérait son indice dans `JOB_COMPLETION_INDEX` pour choisir sa partie des données.

Le champ `ttlSecondsAfterFinished: 600` prévoit la suppression du Job et de ses pods dix minutes après la fin. Ici, les ressources ont été supprimées lors du nettoyage du lab.

### CronJob et suivi

Avec `*/2 * * * *`, le CronJob est prévu toutes les deux minutes. Il a créé automatiquement le Job `bronze-to-silver-pipeline-29867874`, qui s'est terminé correctement. Ses logs indiquaient la fin du traitement simulé des 500 enregistrements.

`concurrencyPolicy: Forbid` empêche deux exécutions de ce CronJob de se chevaucher. Les limites d'historique configurées conservent les trois derniers Jobs réussis et le dernier en échec.

Le CronJob `daily-backup` est programmé à 2 h, heure de Paris, avec `timeZone: Europe/Paris`. Un Job a été déclenché manuellement depuis ce modèle pour le vérifier sans attendre 2 h. Il a affiché `Backup completed`.

La suspension et la reprise de `bronze-to-silver-pipeline` ont été effectuées en passant `suspend` à `true`, puis à `false`. La valeur a été vérifiée après chaque modification.

### Pipeline ETL

Le Job `etl-manual-run` a été créé depuis le CronJob `etl-bronze-to-silver`. Les paramètres de la ConfigMap ont été récupérés par `envFrom`. Les logs confirmaient le passage de `bronze` vers `silver`, un batch de `1000` et la fin du traitement.

Les requests de `100m` CPU et `64Mi` mémoire servent au placement du pod par le scheduler. La limite mémoire est de `128Mi` ; un dépassement peut entraîner un arrêt `OOMKilled`.

Le namespace `lab-job-cronjob` a ensuite été supprimé. La commande pour le retrouver renvoyait `NotFound`. Le cluster minikube a été arrêté après ce nettoyage.
