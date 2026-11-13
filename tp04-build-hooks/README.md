# TP04 — Builds et hooks post-commit

> Durée estimée : 55 min · Module 4 · Projet de travail : le vôtre

**Avant de commencer, faites place nette** : `../scripts/place-nette.sh`.

## 🎬 Le contexte

Hier, les images étaient construites sur un poste. Résultat : personne ne sait dire de quel commit vient celle qui tourne. Aujourd'hui, **c'est OpenShift qui construit** l'API, à partir du dépôt Git, et qui la déploie dès qu'elle est prête.

Reste un risque : une version qui compile, qui démarre… et qui vend le miel à un prix négatif. Vous poserez un **garde-fou** qui l'arrête avant le registre.

```
  dépôt Git ──> BuildConfig api ──> build api-N ──[ hook post-commit ]──> api:latest ──déclencheur──> Deployment api
  poste ──oc start-build --from-dir──┘                    │ code ≠ 0
                                                          └──> build Failed, rien n'est publié
```

## 🎯 Objectif vérifiable

`./verify.sh` applique vos manifestes, attend le build lancé par le déclencheur, contrôle que le Deployment a reçu l'image construite, puis envoie depuis le poste une **version défectueuse** : son build doit finir `Failed` (`PostCommitHookFailed`), `api:latest` ne doit pas bouger, et l'API doit continuer de répondre.

---

## Étape 1 — Un premier build, à la main

```bash
oc new-build --name=essai --strategy=docker \
  https://github.com/aboigues/openshift-formation#main --context-dir=apps/telemarche \
  --labels=app.kubernetes.io/part-of=telemarche
oc logs -f buildconfig/essai
```

> 🎯 **Pendant que le build tourne, prédis :** où s'exécute-t-il ? Sous quel compte ? Où ira l'image ?

```bash
oc get builds,pods
oc describe build essai-1 | head -30
oc get imagestream essai
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Dans un **pod** de votre projet (`essai-1-build`), sous le compte de service `builder`, qui a le droit de pousser dans le registre du projet. L'image arrive sous `essai:latest`. `oc describe build` donne le **commit** construit et l'**empreinte** de l'image produite : on sait toujours d'où vient ce qui tourne.
</details>

```bash
oc delete all -l build=essai
```

## Étape 2 — La recette, dans un fichier

Complétez `starter/build.yaml` (`# TODO 1` à `6`). Le bloc `postCommit`, vers la fin du fichier, attend l'étape 5 : mettez pour l'instant ses trois lignes en commentaire (un `#` devant chacune).

```bash
oc apply -f starter/build.yaml
oc get builds -w                      # Ctrl+C quand le build est Complete
```

Vous n'avez lancé aucun build : c'est le déclencheur `ConfigChange` qui l'a fait.

## Étape 3 — Relier le build au déploiement

Complétez `starter/api.yaml` (`# TODO 9`), puis :

```bash
oc apply -f starter/api.yaml
oc rollout status deployment/api
curl -sk "https://$(oc get route api -o jsonpath='{.spec.host}')/version"; echo
```

> 🎯 **Prédis :** vous relancez un build (`oc start-build api --follow`). Faudra-t-il une commande de plus pour que la nouvelle image soit déployée ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Aucune : `oc get pods -w` montre un nouveau pod dès la fin du build. L'annotation `image.openshift.io/triggers` fait réécrire l'image du Deployment chaque fois que `api:latest` change.
</details>

## Étape 4 — Construire depuis son poste

Le code n'est pas encore poussé ? On l'envoie directement au build :

```bash
oc start-build api --from-dir=.. --follow
oc get builds
```

`--from-dir=..` envoie le dépôt entier, tel qu'il est sur votre disque : le BuildConfig n'en garde que son `contextDir`, comme pour un dépôt Git. La colonne `FROM` distingue les deux origines : `Git@<commit>` et `Binary`.

## Étape 5 — Le garde-fou

L'API sait se contrôler elle-même : `/app/api --self-test` vérifie la version et le catalogue qu'elle embarque, puis renvoie 0 ou 1. Retirez les `#` du bloc `postCommit`, complétez-le (`# TODO 7` et `8`), appliquez, relancez un build :

```bash
oc apply -f starter/build.yaml
oc start-build api --follow | grep -i -B2 -A2 self-test
```

Fabriquez maintenant la version défectueuse : le catalogue de `pannes/` contient un prix négatif et un identifiant en double.

```bash
rm -rf /tmp/depot-panne && mkdir -p /tmp/depot-panne/apps && cp -R ../apps/telemarche /tmp/depot-panne/apps/
cp pannes/catalogue.json /tmp/depot-panne/apps/telemarche/cmd/api/catalogue.json
oc get imagestreamtag api:latest -o jsonpath='{.image.metadata.name}'; echo     # l'empreinte AVANT
oc start-build api --from-dir=/tmp/depot-panne --follow
```

> 🎯 **Prédis :** la compilation réussit. Que devient l'image ? Et l'API en service ?

```bash
oc get builds
oc get imagestreamtag api:latest -o jsonpath='{.image.metadata.name}'; echo     # l'empreinte APRÈS
curl -sk "https://$(oc get route api -o jsonpath='{.spec.host}')/api/products" | head -c 200; echo
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Le build est `Failed (PostCommitHookFailed)`. L'image a bien été construite, mais **jamais poussée** : l'empreinte de `api:latest` n'a pas changé, aucun déploiement n'a eu lieu, le miel est toujours à son prix.
</details>

## Étape 6 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

`verify.sh` ne dépend pas de GitHub : il sert votre copie de travail aux builds, depuis un petit dépôt Git lancé dans le projet de vérification.

---

## 💡 Indices

<details>
<summary>Le build reste <code>New</code> ou <code>Pending</code></summary>

Un build est un pod : il consomme le quota du projet. `oc describe build <nom>` et `oc get events --sort-by=.lastTimestamp | tail`. Supprimez les pods inutiles.
</details>

<details>
<summary><code>build strategy Docker is not allowed</code></summary>

Sur un cluster partagé, la stratégie Docker peut être réservée. Votre formateur vous indiquera la variante en stratégie Source ; le hook post-commit s'écrit de la même façon.
</details>

<details>
<summary>Le hook échoue toujours, même avec le bon catalogue</summary>

`oc logs build/<nom> | tail`. Avec la forme `script`, la commande passe par `/bin/sh` : sur une image sans shell, elle échoue avant même d'appeler l'application. La forme `command` n'a besoin que du binaire.
</details>

<details>
<summary>Le build réussit, mais rien n'est redéployé</summary>

Le déclencheur n'est pas posé, ou ne désigne pas le bon conteneur : `oc set triggers deployment/api` l'affiche. Le nom dans `fieldPath` est celui du **conteneur**, pas du Deployment.
</details>

## 🚀 Pour aller plus loin

- Remplacez la forme `command` par la forme `script` : `oc set build-hook buildconfig/api --post-commit --script="/app/api --self-test"`. Fonctionne-t-elle sur cette image ? Pourquoi ?
- Ajoutez un déclencheur `ImageChange` sur l'image de base : que se passera-t-il quand `ubi-micro:10.3` recevra un correctif ?
- Lisez l'adresse du webhook générique (`oc describe buildconfig api`) : que faudrait-il à votre forge logicielle pour l'appeler ?
