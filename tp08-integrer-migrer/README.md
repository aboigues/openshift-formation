# TP08 — Intégrer et migrer : Télécaisse

> Durée estimée : 1 h 30 · Module 8 · Projet de travail : le vôtre, plus un projet « SI »

**Avant de commencer, faites place nette** : `../scripts/place-nette.sh`.

## 🎬 Le contexte

**Télécaisse**, la caisse des magasins Telemach, est une application Jakarta EE qui tourne sur un WildFly installé à la main (`heritage/`). Chaque mise à jour coupe les caisses ; l'adresse de la base et son mot de passe sont écrits dans `standalone.xml` ; les prix sont recopiés chaque nuit depuis Télémarché, et la caisse vend aux prix de la veille quand la copie échoue.

Vous allez la migrer sur OpenShift **sans déménager sa base**, qui reste dans le système d'information :

```
                     votre projet                                      projet « SI »
  Route telecaisse ──> telecaisse (WildFly) ──> Service caisse-db ─ ─ DNS ─ ─> si-caisse (PostgreSQL)
                            │  envFrom          (ExternalName)
                            │  Secret telecaisse-db
                            └──> Service api ──> api Télémarché (les prix)
```

| Avant (`heritage/`) | Après |
|---|---|
| WildFly complet, installé à la main | serveur réduit aux couches utiles, construit par l'image `wildfly-s2i` |
| pilote PostgreSQL copié dans `modules/` | apporté par la couche Galleon `postgresql-datasource` |
| `jdbc:postgresql://10.12.0.7…` en dur | `POSTGRESQL_HOST=caisse-db`, un Service `ExternalName` |
| mot de passe en clair dans `standalone.xml` | Secret `telecaisse-db` |
| `prix.csv` copié chaque nuit | appel à `http://api:8080` |

## 🎯 Objectif vérifiable

`./verify.sh` installe la base « du SI » et l'API de Télémarché, applique vos manifestes, attend le build WildFly (plusieurs minutes : Maven télécharge ses dépendances), puis contrôle que Télécaisse lit l'historique de l'ancienne caisse, et qu'une vente est enregistrée **dans la base du SI** au **prix de Télémarché**.

---

## Étape 1 — Lire l'existant

Lisez `heritage/standalone-extrait.xml` et `heritage/procedure-installation.txt`, puis le `pom.xml` de [apps/telecaisse](../apps/telecaisse/).

> 🎯 **Prédis :** dans le `pom.xml`, qu'est-ce qui remplace l'installation de WildFly et la copie du pilote PostgreSQL ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Le plugin `wildfly-maven-plugin` : il **provisionne** un serveur à partir de deux *feature packs* (WildFly et ses sources de données), réduit à deux couches, `jaxrs-server` et `postgresql-datasource`, et y déploie l'application. Le serveur fait partie du résultat du build : plus rien à installer à la main.
</details>

## Étape 2 — La base du SI, et ses identifiants

Pour le TP, la base « du SI » est simulée dans un projet à part :

```bash
./outils/base-si.sh
```

Le script affiche l'adresse de la base et la commande qui crée le Secret `telecaisse-db` dans votre projet. Lancez cette commande, puis :

```bash
oc get secret telecaisse-db -o jsonpath='{.data}'; echo      # en base64, pas chiffré
```

Déployez aussi l'API de Télémarché, à laquelle la caisse demandera ses prix :

```bash
oc apply -f outils/telemarche.yaml
```

## Étape 3 — Construire avec l'image WildFly

Complétez `starter/build.yaml` (`# TODO 1` à `3`), puis :

```bash
oc apply -f starter/build.yaml
oc logs -f buildconfig/telecaisse
```

> 🎯 **Pendant le build, prédis :** l'image produite contient-elle Maven ? Les sources ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Oui : l'image `wildfly-s2i` sert à la fois à construire et à exécuter. Le résultat embarque Maven, le JDK complet et ses outils, d'où sa taille (plus d'un Go). Pour la production, un **build enchaîné** copie seulement `/opt/server` dans l'image `quay.io/wildfly/wildfly-runtime` (voir « Pour aller plus loin »).
</details>

## Étape 4 — Configurer par l'environnement

Complétez `starter/telecaisse.yaml` (`# TODO 4` à `9`). Les variables lues par la source de données sont dans [apps/telecaisse/README.md](../apps/telecaisse/README.md).

```bash
oc apply -f starter/telecaisse.yaml
oc rollout status deployment/telecaisse --timeout=10m
CAISSE="https://$(oc get route telecaisse -o jsonpath='{.spec.host}')"
curl -sk "$CAISSE/api/tickets"; echo
```

> 🎯 **Prédis :** `oc run test --rm -it --restart=Never --image=registry.access.redhat.com/ubi10/ubi-minimal:10.3 -- getent hosts caisse-db`. Que répond le DNS du cluster ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Un alias (CNAME) vers `si-caisse.<projet SI>.svc.cluster.local`, puis son adresse. Un Service `ExternalName` n'a ni pod ni adresse IP propre : c'est un nom, rien de plus. Pour une vraie base hors du cluster, on y met son nom DNS ; si elle n'a qu'une adresse IP, on utilise un Service **sans sélecteur** et un `EndpointSlice` écrit à la main.
</details>

## Étape 5 — Une vente, au prix du jour

```bash
curl -sk -X POST -H 'Content-Type: application/json' -d '{"produit":2,"quantite":3}' "$CAISSE/api/ventes"; echo
oc exec deployment/telecaisse -- curl -s http://api:8080/api/products/2; echo   # le prix que donne Télémarché
```

> 🎯 **Prédis :** arrêtez l'API (`oc scale deployment/api --replicas=0`) et repassez une vente. Que répond la caisse ? Et `oc get pods` : Télécaisse redémarre-t-elle ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

`502` : « Télémarché injoignable ». La caisse refuse de vendre plutôt que de vendre à un prix inconnu, et elle ne redémarre pas : sa sonde de vie ne dépend ni de Télémarché, ni de la base. Remettez l'API : `oc scale deployment/api --replicas=1`.
</details>

## Étape 6 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

---

## 💡 Indices

<details>
<summary>Le build échoue sur <code>OOMKilled</code> ou s'arrête sans message</summary>

Maven et le provisionnement du serveur demandent de la mémoire : `resources.limits.memory` du BuildConfig (1536 Mi dans le fichier). Sur CRC, vérifiez la mémoire donnée à la machine virtuelle (`crc config get memory`).
</details>

<details>
<summary>Le build échoue sur <code>Could not transfer artifact</code></summary>

Le pod de build doit joindre `repo1.maven.org`. Derrière un proxy d'entreprise, Maven a besoin d'un miroir : variable `MAVEN_MIRROR_URL` dans `sourceStrategy.env`.
</details>

<details>
<summary>Le pod reste <code>0/1</code> : <code>base : Connection refused</code> ou <code>UnknownHost</code></summary>

`oc get service caisse-db -o yaml` : l'adresse est-elle complète (`si-caisse.<projet>.svc.cluster.local`) ? Et `oc set env deployment/telecaisse --list` : une variable `POSTGRESQL_SERVICE_HOST` l'emporterait sur `POSTGRESQL_HOST`. Kubernetes la pose d'office si votre projet contient un Service nommé `postgresql`.
</details>

<details>
<summary><code>password authentication failed for user "caisse"</code></summary>

Le Secret ne contient pas le mot de passe de la base. Recréez-le avec la commande qu'affiche `./outils/base-si.sh` (relancez-le, il ne change rien à la base).
</details>

## 🚀 Pour aller plus loin

- Build enchaîné : un second BuildConfig, stratégie Docker, `FROM quay.io/wildfly/wildfly-runtime:2.3.0-jdk21`, qui copie `/opt/server` depuis `telecaisse:latest` (`source.images`). De combien l'image rétrécit-elle ?
- Remplacez l'`ExternalName` par un Service sans sélecteur et un `EndpointSlice` portant l'adresse IP du pod `si-caisse`. Que se passe-t-il quand ce pod redémarre ?
- La base du SI n'accepte que les connexions chiffrées, signées par l'autorité de certification de l'entreprise : comment fournir ce certificat à la JVM sans reconstruire l'image ? (Indice : une ConfigMap `ca-entreprise` montée en volume, et la variable `POSTGRESQL_URL`.)
