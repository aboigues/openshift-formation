# TP01 — Déployer et gérer une application

> Durée estimée : 1 h · Module 1 · Projet de travail : le vôtre (`oc project`)
> Prérequis : `oc` installé et connecté (`oc whoami`), voir [docs/environnements.md](../docs/environnements.md).

**Avant de commencer, faites place nette** : `../scripts/place-nette.sh` supprime de votre projet les objets des TP, et eux seuls.

## 🎬 Le contexte

Telemach ouvre **Télémarché**, sa boutique de produits frais. Deux images sont déjà publiées : la vitrine (`telemarche-web`) et l'API (`telemarche-api`). Votre mission : les faire tourner sur OpenShift, publier la vitrine en HTTPS, puis apprendre à les gérer au quotidien.

```
  navigateur ──https──> Route web ──> Service web ──> pods web
                                                        │  API_URL
                                          Service api <─┘──> pods api  <── ConfigMap api-config
```

Vous allez d'abord tout faire **à la main**, avec `oc new-app` et ses cousines : c'est le prototype. Puis vous écrirez ce qui doit durer dans des fichiers : c'est ce que vérifie `verify.sh`.

## 🎯 Objectif vérifiable

`starter/` décrit web et api (Deployment, Service, Route HTTPS, ConfigMap) et la conversion d'une DeploymentConfig. `./verify.sh` l'applique, interroge la vitrine **par sa Route, en HTTPS**, met l'API à jour en 1.1, revient en 1.0, et contrôle que `stock` est devenu un Deployment.

---

## Étape 1 — Se repérer

```bash
oc whoami ; oc whoami --show-server
oc project                       # votre projet courant
oc status                        # ce qu'il contient
```

Sur le Developer Sandbox, votre projet existe déjà et vous ne pouvez pas en créer : `oc new-project` y est refusé.

## Étape 2 — Déployer l'API à partir de son image

> 🎯 **Avant de lancer la commande suivante, prédis :** quels objets `oc new-app` va-t-il créer ? L'application sera-t-elle joignable depuis votre navigateur ?

```bash
oc new-app --name=api \
  --image=docker.io/telemachlearning/telemarche-api:1.0 \
  --labels=app.kubernetes.io/part-of=telemarche
oc get all -l app=api
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Trois objets : un **ImageStream**, un **Deployment** et un **Service** (sur le port 8080, celui que l'image déclare par `EXPOSE`). Aucune **Route** : rien n'est publié hors du cluster tant que vous ne le demandez pas. Pas de sondes, pas de ressources, un seul réplica : `oc new-app` démarre vite, il ne règle rien pour la production.
</details>

<details>
<summary>🔍 Cette commande, option par option</summary>

- `--name=api` : le nom de tous les objets créés, et la valeur de leur label `app`.
- `--image=…` : une image déjà publiée. Le nom est **complet**, registre compris.
- `--labels=app.kubernetes.io/part-of=telemarche` : un label de plus, posé partout. La console s'en sert pour regrouper les composants d'une application, et `place-nette.sh` pour les retrouver.
</details>

```bash
oc logs deployment/api
oc rsh deployment/api          # échoue : pourquoi ?
oc debug deployment/api --image=registry.access.redhat.com/ubi10/ubi-minimal:10.3
```

L'image de l'API est *distroless* : elle ne contient aucun shell, `oc rsh` n'a rien à lancer. `oc debug` crée une copie du pod avec l'image de votre choix. Dans ce shell, tapez `id` : vous n'êtes ni root, ni l'utilisateur prévu par l'image. Ce sera le sujet du module 2. Sortez par `exit`.

## Étape 3 — Déployer la vitrine et la publier

```bash
oc new-app --name=web \
  --image=docker.io/telemachlearning/telemarche-web:1.0 \
  --labels=app.kubernetes.io/part-of=telemarche
oc expose service/web
oc get route web
```

Ouvrez l'adresse affichée. La page s'affiche… en HTTP seulement, et l'API « ne répond pas ».

> 🎯 **Prédis :** la vitrine relaie `/api/` vers `http://api` (sa variable `API_URL`, voir [apps/telemarche](../apps/telemarche/README.md)). Pourquoi cela échoue-t-il, alors que le Service `api` existe ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

`http://api` vise le port **80**. Or `oc new-app` a créé le Service sur le port **8080** : `oc get service api`. Il faut le dire à la vitrine :

```bash
oc set env deployment/web API_URL=http://api:8080
```

Modifier le modèle de pod relance un déploiement : `oc rollout status deployment/web`.
</details>

Passez maintenant en HTTPS. `oc expose` ne sait créer que des Routes HTTP : on la remplace.

```bash
oc delete route web
oc create route edge web --service=web --insecure-policy=Redirect
curl -sI "http://$(oc get route web -o jsonpath='{.spec.host}')/" | head -3
```

La réponse `302` renvoie vers `https://` : c'est l'effet de `--insecure-policy=Redirect`.

## Étape 4 — Configurer, dimensionner

```bash
oc create configmap api-config --from-literal=LOG_LEVEL=debug
oc label configmap api-config app.kubernetes.io/part-of=telemarche
oc set env deployment/api --from=configmap/api-config
oc logs deployment/api | grep -c level=DEBUG      # après quelques requêtes sur la page

oc scale deployment/api --replicas=2
oc set resources deployment/api --requests=cpu=50m,memory=32Mi --limits=memory=64Mi
oc describe quota ; oc describe limitrange          # ce que votre projet vous accorde
```

Rechargez la page plusieurs fois : le nom du pod de l'API change. Le Service répartit le trafic entre les réplicas.

## Étape 5 — Mettre à jour, revenir en arrière

```bash
oc set image deployment/api api=docker.io/telemachlearning/telemarche-api:1.1
oc rollout status deployment/api
oc rollout history deployment/api
oc rollout undo deployment/api
oc rollout history deployment/api
```

Comparez les deux historiques : le retour arrière n'efface rien, il **rejoue** une révision ancienne sous un nouveau numéro.

## Étape 6 — Du prototype aux fichiers

Ce que vous venez de créer à la main n'existe que dans le cluster. Complétez `starter/api.yaml` et `starter/web.yaml` (`# TODO 1` à `9`), puis remplacez le prototype :

```bash
../scripts/place-nette.sh
oc apply -f starter/api.yaml -f starter/web.yaml
oc get deployment,service,route
```

Pour comparer avec ce qu'aurait donné un export : `oc get deployment/api -o yaml`. Tout ce qui appartient au cluster (`status`, `uid`, `resourceVersion`, `managedFields`…) est à retirer avant de versionner.

## Étape 7 — Reconnaître une DeploymentConfig, et la convertir

Un collègue vous transmet `heritage/stock-dc.yaml`, déployé il y a des années.

```bash
oc apply -f heritage/stock-dc.yaml
oc get dc,rc,pods -l app=stock
```

Relevez les indices d'une DeploymentConfig : `oc get dc`, un ReplicationController, un pod `stock-1-deploy`. Puis convertissez-la : complétez `starter/stock.yaml` (`# TODO 10` à `14`).

```bash
oc delete dc stock
oc apply -f starter/stock.yaml
oc get deployment stock -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

> Si votre cluster n'a plus l'API DeploymentConfig (`error: no matches for kind "DeploymentConfig"`), lisez seulement le fichier : la conversion se fait de la même façon.

L'image affichée n'est pas celle du fichier : le **déclencheur** l'a remplacée par l'empreinte (`@sha256:…`) que désigne l'ImageStream.

## Étape 8 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

---

## 💡 Indices

<details>
<summary><code>Unauthorized</code>, ou <code>You must be logged in to the server</code></summary>

Votre jeton a expiré. Console web, menu de votre compte, **Copy login command**, puis collez la commande `oc login --token=…`.
</details>

<details>
<summary>La page s'affiche, mais « L'API ne répond pas »</summary>

`API_URL` ne désigne pas le Service de l'API : `oc set env deployment/web --list`, puis `oc get service api` pour le port. Depuis la vitrine, l'adresse est `http://api:8080`.
</details>

<details>
<summary><code>oc apply</code> refuse <code>starter/stock.yaml</code></summary>

Lisez le message : il nomme le champ refusé. `selector` attend `matchLabels`, `strategy.type` n'accepte que `RollingUpdate` ou `Recreate`. Le tableau de correspondance est dans le support (module 1, « Migrer une DeploymentConfig vers un Deployment »).
</details>

<details>
<summary>Un pod reste <code>Pending</code> après la mise à l'échelle</summary>

Le quota du projet est atteint : `oc describe quota`, puis `oc get events --sort-by=.lastTimestamp | tail`.
</details>

## 🚀 Pour aller plus loin

- Exportez vos objets (`oc get deployment/api service/api -o yaml`), nettoyez l'export, et comparez-le à `solution/api.yaml`.
- `oc diff -f starter/` après un `oc scale` manuel : que montrerait une revue avant d'appliquer ?
- Déployez [`apps/bonjour`](../apps/bonjour/) depuis son code source, sans Dockerfile : un avant-goût du jour 2.
