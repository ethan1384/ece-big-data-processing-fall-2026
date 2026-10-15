# Module 06 — Compte rendu d’exécution des trois labs

Exécution réelle sur la machine de l’étudiant, terminée le 15/10/2026 à 15:56 (CEST).
Les trois labs ont été exécutés sur un cluster local dédié `ece-module06`.
Les observations ci-dessous proviennent des journaux joints.

| Lab | Résultat | Preuve détaillée |
| --- | --- | --- |
| 1 — Kubernetes basics | Terminé | [lab1.log](lab1.log) |
| 2 — ConfigMap et Secret | Terminé | [lab2.log](lab2.log) |
| 3 — Job et CronJob | Terminé | [lab3.log](lab3.log) |

## Environnement

- Windows, Docker Desktop et Ubuntu 24.04 via WSL 2.
- minikube v1.39.0 ; Kubernetes v1.34.1 ; runtime containerd 2.3.4.
- Profil et contexte Kubernetes : `ece-module06`.
- Configuration du cluster et kubeconfig isolés dans le dossier de travail de cette exécution.
- Les manifests appliqués sont conservés dans [manifests](manifests/).

## Lab 1 — Déploiement, Service, scaling et mises à jour

1. Le nœud est devenu `Ready`. Les composants de `kube-system` ont été listés et le nœud décrit.
2. L’addon metrics-server a été activé. La première interrogation a signalé que l’API n’était pas encore disponible ; la suivante a renvoyé des mesures CPU et mémoire réelles.
3. L’image `gcr.io/google-samples/kubernetes-bootcamp:v1` a démarré. Le premier pod était `kubernetes-bootcamp-658f6cbd58-ltjmd`, à l’adresse `10.244.0.12`.
4. Le conteneur utilise Debian GNU/Linux 8 (jessie). Le fichier `/server.js`, consulté dans un shell Bash du conteneur, écoute sur le port `8080`. `curl localhost:8080` a renvoyé `Hello Kubernetes bootcamp! ... v=1`.
5. Avant l’exposition, l’accès à l’IP du pod depuis Ubuntu/WSL a échoué avec le code curl `28` : le réseau du pod n’est pas directement accessible depuis cet environnement hôte.
6. Le Service `NodePort` a exposé le port applicatif `8080` sur le port `31576` du nœud. L’accès depuis l’hôte a été confirmé par un tunnel `kubectl port-forward`, puis arrêté.
7. Après le passage à cinq réplicas, plusieurs requêtes au NodePort ont été servies par **3 pods distincts** : le Service répartit les nouvelles connexions entre ses endpoints. Le nombre de pods a ensuite été ramené à deux et confirmé.
8. Pendant la mise à jour `v1 → v2`, **80 requêtes HTTP ont réussi**, dont 8 réponses `v=1` et 72 réponses `v=2`. Aucune requête de cette série n’a échoué.
9. L’image `jocatalin/kubernetes-bootcamp:v3` a volontairement provoqué un `ErrImagePull`/`ImagePullBackOff`. Le rollout n’a pas abouti, et le Service a continué à répondre en `v=2` grâce aux anciens pods prêts.
10. Un premier rollback a restauré `v2`. L’historique a ensuite permis un retour explicite à la révision 1, confirmé par les réponses `v=1`.
11. Le déploiement déclaratif a été appliqué avec un réplica, puis avec les **trois réplicas** du fichier complété. L’accès HTTP et la répartition entre plusieurs réplicas ont été confirmés.
12. Les Services et le Deployment du lab ont été supprimés.

Le tunnel `port-forward` vise un pod. La répartition de charge a donc été observée séparément en envoyant les requêtes au **NodePort depuis le nœud minikube**.
Le shell du pod a été piloté avec `bash -c`, ce qui permet d’exécuter les manipulations du shell de façon reproductible.
À la création du dernier Service, une première requête a été refusée avant la propagation des règles réseau. La vérification a été reprise après disponibilité du NodePort, puis les trois endpoints prêts et les trois pods répondant en HTTP ont été confirmés. Le journal conserve cette première tentative et la reprise réussie.

Pods observés après le passage à cinq réplicas :

- `kubernetes-bootcamp-658f6cbd58-cr5x9`
- `kubernetes-bootcamp-658f6cbd58-ltjmd`
- `kubernetes-bootcamp-658f6cbd58-xlpw8`

Mesures `kubectl top pods -A --sort-by=cpu --sum=true` enregistrées pendant les labs :

```text
NAMESPACE              NAME                                   CPU(cores)   MEMORY(bytes)   
kube-system            kube-apiserver-ece-module06            109m         187Mi           
kube-system            etcd-ece-module06                      56m          32Mi            
kube-system            kube-controller-manager-ece-module06   33m          53Mi            
kube-system            metrics-server-b85d78fd7-88xc6         15m          15Mi            
kube-system            kube-scheduler-ece-module06            12m          20Mi            
lab-configmap-secret   spark-config-reader                    7m           0Mi             
lab-configmap-secret   spark-app                              6m           0Mi             
lab-configmap-secret   ceph-connector-secure                  5m           0Mi             
kube-system            coredns-66bc5c9577-kj74n               4m           13Mi            
kube-system            storage-provisioner                    4m           8Mi             
kube-system            kindnet-dts9x                          2m           7Mi             
kube-system            kube-proxy-2pl5g                       1m           15Mi            
                                                              ________     ________        
                                                              249m         356Mi
```

`top pods` affiche CPU et mémoire ; `-A` couvre tous les namespaces ; `--sort-by=cpu` trie par CPU ; `--sum=true` ajoute les totaux.
Les rôles des composants sont détaillés dans le fichier de réponses du module. Le cluster possède également un pod `kindnet` pour son réseau CNI.

## Lab 2 — ConfigMap et Secret

- Les trois méthodes de création des ConfigMaps ont été exécutées : fichier properties, valeurs littérales et manifest YAML.
- Les clés `log_level` et `application.yaml` ont été consultées individuellement.
- Les trois méthodes de création des Secrets ont été exécutées, avec les identifiants **fictifs fournis dans l’énoncé**. Les valeurs base64 ont été décodées et comparées aux valeurs initiales. Le décodage a été réalisé en Python, disponible dans Ubuntu, à la place de `jq`.
- Dans `spark-app`, les variables `LOG_LEVEL=INFO` et `SPARK_WORKERS=4` ont été vérifiées.
- `ceph-connector` s’est terminé en `Completed`, et son journal contient la clé d’exemple injectée depuis le Secret.
- Le volume ConfigMap contient `application.yaml` et `tables.csv`. Leurs contenus ont été lus ; la sélection et le renommage de la clé CSV sont effectifs.
- Le volume Secret est monté en lecture seule. Le fichier `s3-credentials.txt` a été lu ; ses permissions observées sont `-rw-------` (`0600`).
- Le namespace `lab-configmap-secret` a été supprimé après les observations.

## Lab 3 — Job, retries, parallélisation et CronJob

| Exercice | Observation réelle |
| --- | --- |
| Job simple | Terminé ; journal : `Starting data import...`, `Processing 1000 records...`, `Import completed!` |
| `backoffLimit: 3`, deadline 300 s | **4 pods** créés ; échec final `BackoffLimitExceeded` |
| Deadline ramenée à 10 s | **1 pod(s)** créé(s) ; échec final `DeadlineExceeded` |
| Job parallèle indexé | **4/4** réussites ; indices **0, 1, 2, 3** présents dans les journaux |
| CronJob toutes les deux minutes | Job automatiquement créé et terminé : `bronze-to-silver-pipeline-29867874` |
| Sauvegarde quotidienne | Schedule `0 2 * * *`, fuseau `Europe/Paris` ; déclenchement manuel terminé avec `Backup completed` |
| Suspension/reprise | Champ `suspend` passé à `true`, puis à `false`, et contrôlé après chaque modification |
| Pipeline ETL | Job manuel terminé ; configuration `bronze → silver`, batch `1000`, journal `Completed!` |

Les pods échoués du Job avec retry restent disponibles pour consulter leurs journaux. Avec `restartPolicy: Never`, chaque nouvelle tentative crée un pod ; la deadline de 10 secondes interrompt le Job avant d’épuiser les retries.
Chaque pod du Job indexé reçoit son shard par `JOB_COMPLETION_INDEX`. Le CronJob planifié a été observé jusqu’à l’exécution réelle d’un Job, sans modification de son horaire.
La sauvegarde de 2 h a été vérifiée en déclenchant un Job depuis son modèle ; son prochain lancement à 2 h n’a pas été attendu.
Les traitements de données sont les simulations pédagogiques de l’énoncé : leurs messages n’attestent pas l’import de données externes réelles.

## Nettoyage et fichiers de preuve

Les namespaces des Labs 2 et 3 et les ressources du Lab 1 ont été supprimés. L’état final et l’arrêt du cluster sont enregistrés dans [nettoyage.log](nettoyage.log).

- [Journal Lab 1](lab1.log), [Lab 2](lab2.log), [Lab 3](lab3.log).
- [80 réponses pendant la mise à jour](lab1-rolling-update-http.log).
- Résultats structurés : [Lab 1](lab1-resultats.json), [Lab 2](lab2-resultats.json), [Lab 3](lab3-resultats.json).
- [Manifests et fichiers appliqués](manifests/).

Les erreurs intentionnelles font partie du TP : IP de pod inaccessible depuis l’hôte, image v3 inexistante, validation du Job systématiquement en échec et deadline dépassée.

Les clés fictives de l’énoncé ont été masquées dans la copie des preuves destinée au dossier du cours. Les commandes, statuts, noms de pods et mesures restent ceux de l’exécution réelle.
