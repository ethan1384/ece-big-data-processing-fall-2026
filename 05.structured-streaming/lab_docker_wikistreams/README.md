# Lab 05 : Structured Streaming avec Kafka et Wikimedia

Ce lab récupère en continu les modifications de Wikipédia, les envoie dans Kafka, puis les agrège avec Spark Structured Streaming dans un notebook Jupyter.

```
Wikimedia EventStreams ──> producteurs Python (sur ta machine) ──> Kafka (Docker) ──> notebook PySpark (Docker)
```

| Fichier | Rôle |
| --- | --- |
| `compose.yaml` | Lance deux conteneurs : `kafka` et `pyspark_notebook` (Jupyter + Spark) |
| `admin_custom.py` | Crée les topics `wikistreams` et `wikistreams_live` |
| `wikistream_producer.py` | Producteur du prof : historique de fr.wikipedia.org vers `wikistreams` (10 min) |
| `wikistream_producer_custom.py` | Notre producteur filtré : modifications en direct de fr, en et de.wikipedia.org vers `wikistreams_live` (10 min) |
| `notebooks/wikistream_pyspark_completed.ipynb` | Notebook rendu : démo du prof + nos 7 explorations et les réponses |
| `notebooks/wikistream_pyspark.ipynb` | Notebook d'origine du prof, non modifié |
| `admin.py`, `wikistream_pyspark.ipynb` | Fichiers d'origine du prof (l'énoncé est `../lab_docker_wikistreams.md`) |

## Prérequis

- Docker Desktop lancé (et pas en pause).
- Python 3.10 ou plus récent sur la machine.
- Ports 9092, 8888 et 4040 libres.

Toutes les commandes se lancent depuis ce dossier :

```bash
cd 05.structured-streaming/lab_docker_wikistreams
```

## 1. Environnement Python (une seule fois)

Les producteurs tournent sur ta machine, pas dans Docker. Ils ont besoin de `confluent-kafka`, `pywikibot` et `requests-sse` (sans ce dernier, pywikibot refuse de lire le flux).

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install confluent-kafka pywikibot requests-sse
```

Le dossier `.venv` est ignoré par git.

## 2. Démarrer Kafka et Jupyter

```bash
docker compose up -d
docker ps          # kafka et pyspark_notebook doivent être "Up"
```

Le premier lancement télécharge les images (quelques Go).

## 3. Créer les topics

Dans chaque terminal où tu lances un script Python :

```bash
source .venv/bin/activate
export PYWIKIBOT_NO_USER_CONFIG=1   # évite à pywikibot de chercher un user-config.py
```

Puis :

```bash
python admin_custom.py
```

Il crée les deux topics, ou affiche juste la liste s'ils existent déjà.

## 4. Lancer les producteurs (deux terminaux)

Terminal 1, historique de fr.wikipedia.org :

```bash
python wikistream_producer.py
```

Terminal 2, flux en direct de plusieurs wikis :

```bash
python wikistream_producer_custom.py
```

Chacun tourne 10 minutes puis s'arrête tout seul (Ctrl+C pour arrêter avant). Le producteur custom accepte des filtres, par exemple :

```bash
python wikistream_producer_custom.py --wikis en.wikipedia.org --titles "Taylor Swift" --minutes 5
python wikistream_producer_custom.py --wikis www.wikidata.org --humans-only --namespaces 0
python wikistream_producer_custom.py --help
```

## 5. Ouvrir et lancer le notebook

Récupérer le lien Jupyter avec son token :

```bash
docker logs pyspark_notebook 2>&1 | grep "127.0.0.1:8888/lab?token"
```

Dans Jupyter, ouvrir `work/wikistream_pyspark_completed.ipynb` (le dossier `notebooks/` est monté dans `work/`), puis Run > Run All Cells.

- Le mieux est de lancer le notebook une fois les producteurs terminés : les topics sont alors complets et les chiffres correspondent aux réponses écrites. Pendant que les producteurs tournent, ça marche aussi, mais les tableaux ne montrent que ce qui est déjà arrivé.
- Le notebook complet prend plusieurs minutes : chaque exploration attend que Spark ait lu tout le topic.
- La Spark UI est sur http://localhost:4040 pendant l'exécution.

Les requêtes `console` (la démo du prof et l'exploration 6) écrivent dans les logs du conteneur :

```bash
docker logs -f pyspark_notebook
```

### Variante sans navigateur

Pour exécuter le notebook en ligne de commande, il faut d'abord sourcer le script qui ajoute PySpark au `PYTHONPATH` (Jupyter le fait tout seul au démarrage, `docker exec` non) :

```bash
docker exec -u jovyan pyspark_notebook bash -lc 'source /usr/local/bin/before-notebook.d/10spark-config.sh && cd /home/jovyan/work && jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=-1 wikistream_pyspark_completed.ipynb'
```

## 6. Arrêter

```bash
docker compose down
```

Le compose n'a pas de volume pour Kafka : `down` efface aussi les topics. C'est d'ailleurs la façon la plus simple de repartir de zéro avant de relancer les producteurs, sinon les messages s'ajoutent à ceux déjà présents et tout est compté en double.

## Problèmes connus

| Symptôme | Cause et solution |
| --- | --- |
| `no configuration file provided: not found` | `docker compose` lancé hors de ce dossier. Faire `cd 05.structured-streaming/lab_docker_wikistreams`. |
| `Docker Desktop is manually paused` | Reprendre Docker Desktop depuis le menu de la baleine (Resume). |
| `requests-sse is required for EventStreams` | `pip install requests-sse` dans la venv. |
| Tableaux vides, `NoSuchMethodError: HDFSMetadataLog` dans les logs | L'image Jupyter actuelle contient Spark 4.2.0 alors que le notebook du prof charge le connecteur Kafka 4.1.0. Le notebook complété contient une cellule (juste après les imports) qui charge le connecteur de la même version que Spark : bien exécuter les cellules dans l'ordre. |
| `No module named 'pyspark'` avec `docker exec` | Sourcer `10spark-config.sh` comme dans la variante sans navigateur. |
| Chiffres doublés par rapport aux réponses | Les producteurs ont tourné deux fois sur les mêmes topics. `docker compose down`, puis reprendre à l'étape 2. |
