# TP06 — Un modèle pour toute l'application

> Durée estimée : 1 h · Module 6 · Projet de travail : le vôtre

**Avant de commencer, faites place nette** : `../scripts/place-nette.sh`.

## 🎬 Le contexte

Télémarché prend ses premières commandes… et en perd. L'API les garde **en mémoire** : chaque pod a les siennes, et un redémarrage les efface. Il lui faut une **base PostgreSQL**, avec un volume qui survive au pod.

L'application compte désormais trois composants, neuf objets, un mot de passe partagé. Les recopier à la main dans chaque projet (développement, recette, formation…) serait une source d'erreurs. Vous allez les réunir dans un **modèle** (`Template`) : un seul objet, des paramètres, et une commande pour tout créer.

```
                            ┌─────────────── modèle « telemarche » ───────────────┐
  Route web ──> web ──> api (2 pods) ──> Service db ──> db (PostgreSQL) ──> PVC db-data
                         │  ▲ conteneur d'initialisation migrate               │
                         └──┴──────── Secret db-credentials ───────────────────┘
```

## 🎯 Objectif vérifiable

`./verify.sh` dépose votre modèle dans le projet, l'instancie avec `oc new-app --template=telemarche`, puis contrôle : un mot de passe tiré au hasard, la migration faite par le conteneur d'initialisation, une commande visible par **les deux** pods de l'API, et toujours là après le redémarrage de la base.

---

## Étape 1 — Le problème

```bash
oc new-app --name=api --image=docker.io/telemachlearning/telemarche-api:1.1 \
  --labels=app.kubernetes.io/part-of=telemarche
oc scale deployment/api --replicas=2
oc expose service/api --port=8080
API="http://$(oc get route api -o jsonpath='{.spec.host}')"
curl -s -X POST -H 'Content-Type: application/json' -d '{"product_id":1,"quantity":2}' "$API/api/orders"; echo
```

> 🎯 **Avant de lancer la boucle suivante, prédis :** combien de commandes chaque appel affichera-t-il ?

```bash
for i in 1 2 3 4 5 6; do curl -s "$API/api/orders"; echo; done
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Une fois sur deux, la liste est vide. Le routeur répartit les appels entre les deux pods, et seul celui qui a reçu la commande la connaît. Supprimez ce pod (`oc delete pod <nom>`) : la commande disparaît pour de bon.
</details>

```bash
oc delete all -l app=api
```

## Étape 2 — Lire un modèle

Ouvrez `starter/telemarche.yaml`. Trois parties :

| Partie | Rôle |
|---|---|
| `parameters` | ce qui change d'une instance à l'autre : version, nombre de pods, mot de passe… |
| `objects` | les objets à créer ; `${NOM}` y est remplacé par la valeur du paramètre |
| `labels` | posés sur **chaque** objet créé : `place-nette.sh` les retrouve tous |

```bash
oc process -f starter/telemarche.yaml --parameters
```

## Étape 3 — Compléter le modèle

Complétez `starter/telemarche.yaml` (`# TODO 1` à `8`) :

| TODO | Ce qu'il faut savoir |
|---|---|
| 1, 2 | un paramètre peut être **généré** : `generate` désigne le générateur, `from` son motif, une expression régulière simplifiée |
| 3 | deux pods ne peuvent pas monter ensemble un volume `ReadWriteOnce` : l'ancien doit s'arrêter avant que le nouveau démarre |
| 4 | `secretKeyRef` relie UNE variable à UNE clé d'un Secret, quand les noms diffèrent |
| 5 | le volume du pod renvoie au `PersistentVolumeClaim` du modèle |
| 6 | `${NOM}` produit une chaîne ; `${{NOM}}` insère la valeur telle quelle, ce qu'exige un nombre |
| 7 | l'image de l'API contient deux programmes : `/app/api` et `/app/migrate` |
| 8 | `envFrom` transforme **toutes** les clés d'un Secret en variables du même nom |

Vérifiez le rendu, sans rien créer :

```bash
oc process -f starter/telemarche.yaml -p API_REPLICAS=2 | less
```

> 🎯 **Prédis :** lancez deux fois `oc process -f starter/telemarche.yaml | grep DB_PASSWORD`. Même mot de passe ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Deux mots de passe différents : il est tiré à chaque instanciation. Retenez-le pour l'étape 6.
</details>

## Étape 4 — Déposer le modèle, puis l'instancier

```bash
oc apply -f starter/telemarche.yaml           # le modèle devient un objet du projet
oc get templates
oc new-app --template=telemarche -p API_REPLICAS=2
oc get pods -w                                # Ctrl+C quand tout est Running
```

Le modèle apparaît aussi dans la console, onglet **+Add**, **All services** : n'importe quel membre du projet peut l'instancier en remplissant un formulaire.

> 🎯 **Prédis :** dans quel ordre les pods démarrent-ils ? Que fait un pod de l'API tant que la base n'est pas prête ?

```bash
oc get pods -l app=api
oc logs <un pod api> -c migrate
```

<details>
<summary>💡 Vérifie ta prédiction</summary>

Les pods de l'API affichent d'abord `Init:0/1` : le conteneur `migrate` attend la base, crée le schéma, puis se termine. Seulement alors le conteneur `api` démarre. Les deux pods jouent la migration ; elle ne fait rien la seconde fois.
</details>

## Étape 5 — Une seule mémoire

```bash
WEB="https://$(oc get route web -o jsonpath='{.spec.host}')"
curl -sk -X POST -H 'Content-Type: application/json' -d '{"product_id":2,"quantity":1}' "$WEB/api/orders"; echo
for i in 1 2 3 4; do curl -sk "$WEB/api/orders"; echo; done
oc delete pod -l app=db
oc get pods -l app=db -w                      # Ctrl+C quand le nouveau pod est prêt
curl -sk "$WEB/api/orders"; echo
```

Chaque réponse contient la commande, quel que soit le pod qui répond, et elle a survécu à la base : elle est dans le volume `db-data`. Le champ `pod` dit quel pod de l'API l'a enregistrée.

## Étape 6 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

---

## 💡 Indices

<details>
<summary>Le Deployment api est refusé : <code>replicas</code> n'est pas un nombre</summary>

`replicas` a reçu une chaîne (`"2"`). Utilisez la forme `${{…}}`.
</details>

<details>
<summary>Le pod <code>db</code> reste <code>Pending</code></summary>

`oc describe pvc db-data` : le cluster doit fournir une classe de stockage par défaut. Sur CRC, c'est le cas. Sur un autre cluster, demandez laquelle utiliser (`oc get storageclass`).
</details>

<details>
<summary>Les pods de l'API restent en <code>Init:0/1</code></summary>

`oc logs <pod> -c migrate`. `password authentication failed` : le Secret a changé après la création de la base (un second `oc process | oc apply`, par exemple). Recommencez proprement : `../scripts/place-nette.sh`, puis l'étape 4.
</details>

<details>
<summary><code>oc new-app</code> répond <code>already exists</code></summary>

Une instance tourne déjà dans le projet. `../scripts/place-nette.sh` supprime tout ce qu'a créé le modèle, puis relancez.
</details>

## 🚀 Pour aller plus loin

- Instanciez une seconde fois le modèle dans le même projet. Que faudrait-il paramétrer pour que les deux instances cohabitent ?
- `oc process -f starter/telemarche.yaml | oc apply -f -` une seconde fois, sans `-p DB_PASSWORD=…` : que devient le mot de passe ? La base l'accepte-t-elle ? (Indice : l'image PostgreSQL réapplique le mot de passe à chaque démarrage.)
- Comparez avec un chart Helm (`helm create`) : qu'apporte Helm de plus qu'un modèle ? Qu'apporte le modèle que Helm n'a pas ?
