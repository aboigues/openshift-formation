# TP02 — Concevoir une image pour OpenShift

> Durée estimée : 50 min · Module 2 · Projet de travail : le vôtre
> Outils : `oc` ; `podman` ou `docker` si votre poste en dispose (facultatif, mais vous irez plus vite).

**Avant de commencer, faites place nette** : `../scripts/place-nette.sh`.

## 🎬 Le contexte

L'équipe de Télémarché vous confie l'image « historique » de son API : [`heritage/Dockerfile`](heritage/Dockerfile). Elle tourne depuis des années sur un serveur Docker. Sur OpenShift, elle ne démarre pas.

Votre mission : comprendre pourquoi, puis réécrire le Dockerfile pour qu'elle démarre **sans aucun droit supplémentaire**.

## 🎯 Objectif vérifiable

`./verify.sh` construit **votre** `starter/Dockerfile` dans le cluster et déploie l'image telle quelle. Elle doit démarrer sous la contrainte `restricted-v2` (UID imposé, groupe 0), écrire son journal, peser moins de 150 Mo, et s'arrêter en moins de 20 secondes.

---

## Étape 1 — Lire l'image historique

Ouvrez `heritage/Dockerfile` et `heritage/demarrer.sh`.

> 🎯 **Avant d'aller plus loin, prédis :** relevez tout ce qui, dans ces deux fichiers, pose un problème sur OpenShift ou contredit les principes du module (KISS, YAGNI, séparation des responsabilités). Notez votre liste : vous la comparerez à l'étape 3.

## Étape 2 — La faire échouer

**Sur votre poste** (si vous avez podman ou docker) :

```bash
rm -rf /tmp/heritage && cp -R ../apps/telemarche /tmp/heritage && cp heritage/* /tmp/heritage/
podman build -t api-heritage /tmp/heritage
podman run --rm -p 8080:80 api-heritage                    # fonctionne : curl localhost:8080/version
podman run --rm -p 8080:80 --user 12345:0 api-heritage     # comme sur OpenShift
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- Le Dockerfile attend, dans son contexte de construction, les sources de l'application **et** `demarrer.sh` : on rassemble les deux dans `/tmp/heritage`.
- `-p 8080:80` : le port 8080 de votre poste mène au port 80 du conteneur.
- `--user 12345:0` : lance le conteneur avec un UID que l'image ne connaît pas, et le groupe 0. C'est exactement ce que fait OpenShift.
</details>

**Sur OpenShift** :

```bash
./outils/deployer.sh heritage
oc get pods -l app=api-heritage
oc logs deployment/api-heritage
```

`deployer.sh` construit l'image dans le cluster et la déploie (les builds sont le sujet de demain). Le pod passe en `CrashLoopBackOff`.

> 🎯 **Prédis :** une fois la première erreur corrigée, l'image démarrera-t-elle ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Non : une erreur en cache une autre. Le journal montre d'abord `open /app/journal/commandes.log: permission denied` (le répertoire appartient à root, droits `755`). Ce problème réglé, vient `listen tcp :80: bind: permission denied` (un port inférieur à 1024 exige des privilèges). Pour voir la seconde sans corriger l'image :

```bash
podman run --rm --user 12345:0 --tmpfs /app/journal:rw,mode=1777 api-heritage
```
</details>

Regardez aussi comment elle s'arrête, lancée en root :

```bash
podman run -d --name h -p 8080:80 api-heritage && sleep 3 && time podman stop -t 30 h ; podman rm h
```

Trente secondes : `demarrer.sh` est le processus n° 1 et ne transmet pas `SIGTERM` à l'API, qui finit tuée par `SIGKILL`.

## Étape 3 — Réécrire le Dockerfile

Complétez `starter/Dockerfile` (`# TODO 1` à `8`). Chaque trou correspond à un défaut de l'image historique :

| Défaut de l'image historique | Correction |
|---|---|
| Une seule étape : compilateur et sources livrés (1,3 Go) | Deux étapes, image finale `ubi-micro` |
| `USER root` | `USER` numérique, différent de 0 |
| `/app/journal` réservé à root | groupe `0`, droits `g=u` |
| Port 80 | Port supérieur à 1024 |
| `ENTRYPOINT` en forme shell, script sans `exec` | forme exec |
| Aucune version, aucun label | `ARG`, `LABEL` |

## Étape 4 — Tester comme sur OpenShift, avant OpenShift

```bash
podman build -f starter/Dockerfile -t telemarche-api:dev ../apps/telemarche
podman run --rm --user 12345:0 -p 8080:8080 telemarche-api:dev
podman images | grep -E 'api-heritage|telemarche-api'        # comparez les tailles
```

Si l'application répond avec un UID quelconque et le groupe 0, elle démarrera sur OpenShift. Sans podman ni docker, passez directement à l'étape suivante : c'est le cluster qui construira.

## Étape 5 — Déployer et valider

```bash
./outils/deployer.sh starter
oc get pods -l app=api-starter
oc rsh deployment/api-starter id        # l'UID n'est ni 0, ni 1001
oc get pod -l app=api-starter -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}'; echo

./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

---

## 💡 Indices

<details>
<summary><code>chgrp: changing group of '/app/journal': Operation not permitted</code> pendant la construction</summary>

L'instruction `RUN` qui change les droits est placée **après** `USER 1001` : on n'est plus root. Les changements de droits se font avant de quitter root.
</details>

<details>
<summary>Le pod démarre, mais le Service ne répond pas</summary>

Le port a été changé dans `EXPOSE` et pas dans l'application : c'est la variable `PORT` qui décide du port d'écoute. `oc logs deployment/api-starter` l'affiche (`port=…`).
</details>

<details>
<summary><code>Permission denied</code> persiste</summary>

`oc logs` nomme le fichier refusé. Vérifiez les droits dans l'image : `oc debug deployment/api-starter -- ls -ld /app/journal`. Il faut `drwxrwxr-x … root` : groupe 0, et le groupe autorisé à écrire.
</details>

<details>
<summary>Le build échoue sur <code>go.mod requires go >= 1.27</code></summary>

L'image de l'étape de compilation est trop ancienne pour ce code. Gardez `go-toolset:10.3`.
</details>

## 🚀 Pour aller plus loin

- Lancez votre image avec un système de fichiers en lecture seule : `podman run --rm --user 12345:0 --read-only --tmpfs /app/journal -p 8080:8080 telemarche-api:dev`. Que faudrait-il au Deployment pour tourner ainsi ?
- Le journal écrit dans le conteneur disparaît avec le pod. Quel principe du module cela contredit-il ? Proposez deux corrections (indice : `JOURNAL_DIR` vide, ou un volume).
- Ajoutez un `.containerignore` et mesurez l'effet d'une modification du README sur le cache de construction.
