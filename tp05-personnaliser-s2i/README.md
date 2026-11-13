# TP05 — Personnaliser Source-to-Image

> Durée estimée : 1 h · Module 5 · Projet de travail : le vôtre

**Avant de commencer, faites place nette** : `../scripts/place-nette.sh`.

## 🎬 Le contexte

Source-to-Image construit une application sans Dockerfile : du code, une image de construction, et c'est tout. Encore faut-il que l'image de construction sache quoi faire du dépôt. Celui de Télémarché contient **deux programmes** (`cmd/api` et `cmd/web`) : l'image `go-toolset` ne sait pas lequel choisir.

Vous allez lever cette limite deux fois : d'abord **dans le dépôt de l'application** (niveau 2), puis **dans une image de construction** que toute l'équipe pourra réutiliser (niveau 3).

| Niveau | Où | Dossier du TP |
|---|---|---|
| 1 | variables prévues par l'image | `starter/depot/.s2i/environment` |
| 2 | scripts dans le dépôt de l'application | `starter/depot/.s2i/bin/` |
| 3 | image de construction sur mesure | `starter/telemach-go-builder/` |

## 🎯 Objectif vérifiable

`./verify.sh` construit la vitrine avec `go-toolset` et **vos** scripts `.s2i/bin`, puis bâtit **votre** image de construction dans le cluster. L'arrivée de cette image doit déclencher, sans autre commande, les builds de web et d'api décrits dans `starter/telemarche.yaml` ; la vitrine doit répondre par sa Route.

---

## Étape 1 — Constater la limite

```bash
oc new-build --name=essai \
  registry.access.redhat.com/ubi10/go-toolset:10.3~https://github.com/aboigues/openshift-formation#main \
  --context-dir=apps/telemarche --labels=app.kubernetes.io/part-of=telemarche
oc logs -f buildconfig/essai
```

> 🎯 **Avant de lire le journal, prédis :** à quelle étape le build va-t-il échouer : récupération des sources, `assemble`, ou publication ?

Lisez ensuite le script fautif :

```bash
oc run lire --rm -it --restart=Never --image=registry.access.redhat.com/ubi10/go-toolset:10.3 \
  -- cat /usr/libexec/s2i/assemble
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

`assemble` échoue : `no Go files in /tmp/src`. Sa dernière ligne lance `go build` à la racine des sources, où il n'y a que `go.mod`. Aucune variable de ce script ne permet de désigner un sous-dossier : le niveau 1 ne suffit pas.
</details>

## Étape 2 — Niveau 2 : des scripts dans le dépôt

Un script placé dans `.s2i/bin/` du dépôt remplace celui de l'image. Complétez `starter/depot/.s2i/bin/assemble` et `run` (`# TODO 1` à `3`), puis envoyez au build les sources **et** vos scripts :

```bash
rm -rf /tmp/depot-s2i && mkdir -p /tmp/depot-s2i/apps && cp -R ../apps/telemarche /tmp/depot-s2i/apps/
cp -R starter/depot/.s2i /tmp/depot-s2i/apps/telemarche/
oc start-build essai --from-dir=/tmp/depot-s2i --follow
```

<details>
<summary>🔍 Ces commandes, une par une</summary>

- On fabrique dans `/tmp/depot-s2i` une copie du dépôt réduite à l'application, à laquelle on ajoute le dossier `.s2i` : c'est ce que contiendrait le dépôt Git si vous y aviez poussé vos scripts.
- `oc start-build --from-dir` envoie ce dossier au build à la place du dépôt Git. Le BuildConfig garde son `contextDir` (`apps/telemarche`).
- La variable `COMPOSANT` vient de `.s2i/environment` : c'est le niveau 1, qui complète ici le niveau 2.
</details>

> 🎯 **Prédis :** l'image produite contient-elle le compilateur Go ? Les sources ?

```bash
oc new-app essai --name=essai --labels=app.kubernetes.io/part-of=telemarche
oc rsh deployment/essai sh -c 'ls /opt/app-root ; ls /tmp/src ; go version'
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Les deux : S2I enregistre le conteneur de construction tel quel. L'image pèse plus d'un gigaoctet. Le remède est un build enchaîné (support, « Séparer construction et exécution »).
</details>

```bash
oc delete all -l app.kubernetes.io/part-of=telemarche
```

## Étape 3 — Niveau 3 : une image de construction

Les scripts du niveau 2 seraient à recopier dans chaque dépôt. On les place une fois pour toutes dans une image. Complétez `starter/telemach-go-builder/Dockerfile` et `s2i/bin/assemble` (`# TODO 4` à `8`).

Si vous avez podman ou docker, essayez-la d'abord sur votre poste :

```bash
podman build -t telemach-go-builder starter/telemach-go-builder
podman run --rm --user 12345:0 telemach-go-builder        # sans sources : le mode d'emploi
```

## Étape 4 — Publier l'image et s'en servir

Complétez `starter/telemarche.yaml` (`# TODO 9` à `12`), puis :

```bash
oc apply -f starter/telemarche.yaml
oc get buildconfig,imagestream
```

> 🎯 **Prédis :** les BuildConfigs `web` et `api` existent. Des builds sont-ils lancés ?

Construisez maintenant l'image de construction, et regardez la suite :

```bash
oc start-build telemach-go-builder --from-dir=starter/telemach-go-builder --follow
oc get builds -w              # Ctrl+C quand web-1 et api-1 sont Complete
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Aucun build tant que `telemach-go-builder:latest` n'existe pas : le déclencheur `ImageChange` attend l'image. Dès qu'elle arrive, `web-1` et `api-1` partent **ensemble**. Demain, un correctif de l'image de construction reconstruira de la même façon toutes les applications qui en dépendent.
</details>

```bash
curl -sk "https://$(oc get route web -o jsonpath='{.spec.host}')/version"; echo
```

## Étape 5 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

---

## 💡 Indices

<details>
<summary>Le build se comporte comme si mon script n'existait pas</summary>

Il n'est pas exécutable. `ls -l starter/depot/.s2i/bin/` ; `chmod +x` si besoin. Dans un dépôt Git, le droit doit être enregistré : `git update-index --chmod=+x .s2i/bin/assemble`.
</details>

<details>
<summary><code>/bin/bash^M: bad interpreter</code></summary>

Le script a des fins de ligne Windows. Réglez votre éditeur sur « LF », ou : `sed -i 's/\r$//' <fichier>`.
</details>

<details>
<summary><code>variable COMPOSANT absente</code></summary>

C'est le message du `${COMPOSANT:?…}` : la variable n'est pas parvenue au build. Niveau 2 : `.s2i/environment` n'a pas été copié. Niveau 3 : `env` du BuildConfig.
</details>

<details>
<summary><code>go.mod requires go >= 1.27</code></summary>

L'image de construction est trop ancienne pour ce code : gardez `go-toolset:10.3`.
</details>

## 🚀 Pour aller plus loin

- Activez le build incrémental (`sourceStrategy.incremental: true`) et comparez les durées de deux builds successifs : `save-artifacts` est déjà dans l'image.
- Ajoutez un build enchaîné qui copie `/opt/app-root/app` de `web:latest` dans `ubi-micro` : de combien l'image rétrécit-elle ?
- Comparez votre image à la référence du dépôt : [`builders/telemach-go-builder`](../builders/telemach-go-builder/), et lancez son `test/run`.
