# TP03 — Registre et droits

> Durée estimée : 45 min · Module 3 · Projet de travail : le vôtre, plus un second projet (ou un voisin, voir l'étape 4)
> Outils : `oc` ; `podman` ou `docker` pour l'étape 1 (facultative sans eux).

**Avant de commencer, faites place nette** : `../scripts/place-nette.sh`.

## 🎬 Le contexte

L'image de l'API est prête (TP02). Reste à la **publier** dans le registre du cluster, à décider **quelle version part en production**, et à régler **qui a le droit de la tirer** : l'équipe de Télémarché construit ses images dans un projet et les exécute dans un autre.

```
  poste ──push──> registre intégré ── projet « images »           projet « prod »
                    ImageStream api                                  Deployment api
                      1.1  ──┐                                          │ tire
                      prod ──┴──> image sha256:…  <── system:image-puller ── compte default
```

## 🎯 Objectif vérifiable

`./verify.sh` applique votre ImageStream (l'étiquette `prod` doit désigner la même image que `1.1`), déploie l'image dans un **second projet**, constate le refus, exécute votre `partager.sh`, et contrôle que le pod démarre. Il exécute enfin `lier-registre.sh` et vérifie que les deux comptes de service présentent le Secret.

---

## Étape 1 — Pousser une image depuis son poste

```bash
PROJET=$(oc project -q)
oc create imagestream essai                       # il faut un ImageStream pour lire l'adresse du registre
REGISTRE=$(oc get imagestream essai -o jsonpath='{.status.publicDockerImageRepository}' | cut -d/ -f1)
echo "$REGISTRE"
```

Si l'adresse est vide, le registre n'est pas exposé hors du cluster : seul un administrateur peut le faire. Passez à l'étape 2.

```bash
podman login -u "$(oc whoami)" -p "$(oc whoami -t)" "$REGISTRE"      # --tls-verify=false sur un cluster de test
podman tag telemarche-api:dev "$REGISTRE/$PROJET/telemarche-api:dev" # l'image du TP02
podman push "$REGISTRE/$PROJET/telemarche-api:dev"
oc get imagestream
```

> 🎯 **Avant de lancer `oc get imagestream`, prédis :** vous n'avez créé aucun ImageStream `telemarche-api`. Y en aura-t-il un ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Oui : pousser une image dans le registre intégré crée l'ImageStream du même nom. Le chemin doit commencer par **votre** projet : poussez vers `$REGISTRE/un-autre-projet/…` et le registre refuse, car vos droits sur les images sont ceux que vous avez sur le projet.
</details>

```bash
oc delete imagestream essai telemarche-api
```

## Étape 2 — Référencer et promouvoir

Complétez `starter/imagestream.yaml` (`# TODO 1` à `5`). Il décrit ce que feraient ces trois commandes :

```bash
oc import-image api:1.1 --confirm --scheduled --from=docker.io/telemachlearning/telemarche-api:1.1
oc tag api:1.1 api:prod
oc set image-lookup api
```

```bash
oc apply -f starter/imagestream.yaml
oc describe imagestream api
oc get imagestreamtag
```

> 🎯 **Prédis :** `oc tag api:1.1 api:prod` copie-t-il l'image ? Combien de temps prendrait la promotion d'une image de 2 Go ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Rien n'est copié : `oc describe imagestream api` montre la **même empreinte** `sha256:…` sous les deux étiquettes. Une promotion est instantanée, quelle que soit la taille de l'image, et l'image promue est exactement celle qui a été testée.
</details>

## Étape 3 — Utiliser l'ImageStream dans un Deployment

```bash
oc create deployment essai --image=api:prod
oc label deployment essai app.kubernetes.io/part-of=telemarche
oc get pods -l app=essai -o jsonpath='{.items[0].spec.containers[0].image}'; echo
```

Le Deployment écrit `api:prod` ; le pod, lui, porte une empreinte. C'est l'effet de `lookupPolicy.local` : sans lui, `api:prod` serait cherché sur Docker Hub.

## Étape 4 — Ouvrir ses images à un second projet

Il vous faut un projet consommateur :

- **vous pouvez créer des projets** : `oc new-project "$(oc whoami | tr -c 'a-z0-9\n' '-')-prod"`, puis `oc project <votre premier projet>` pour y revenir ;
- **sinon (Developer Sandbox)** : travaillez en binôme. Le projet consommateur est celui de votre voisin, qui lance `consommateur.sh` de son côté.

```bash
IMAGES=$(oc project -q)
PROD=<le second projet>
./outils/consommateur.sh "$IMAGES" "$PROD"
oc get pods -n "$PROD" -l app=api
oc describe pod -n "$PROD" -l app=api | tail -6
```

> 🎯 **Prédis :** l'image existe, le nom est juste. Pourquoi `ImagePullBackOff` ?

<details>
<summary>💡 Vérifie ta prédiction</summary>

Le message est `authentication required` (ou `unauthorized`) : par défaut, les pods d'un projet ne peuvent tirer que les images de **leur** projet. Le registre applique les rôles du projet qui possède l'image.
</details>

Complétez `starter/partager.sh` (`# TODO 6` et `7`), puis :

```bash
./starter/partager.sh "$IMAGES" "$PROD"
oc delete pods -n "$PROD" -l app=api        # relance immédiate, sans attendre le prochain essai
oc get pods -n "$PROD" -l app=api
```

## Étape 5 — Les identifiants d'un registre externe

Complétez `starter/lier-registre.sh` (`# TODO 8` à `10`). Essayez-le avec de faux identifiants :

```bash
./starter/lier-registre.sh "$(oc project -q)" registre.exemple.com robot-lecture faux-jeton
oc get serviceaccount default builder -o yaml | grep -B2 -A3 registre-externe
oc secrets unlink default builder registre-externe ; oc delete secret registre-externe
```

## Étape 6 — Validez

```bash
./verify.sh              # teste VOTRE travail (dossier starter/)
./verify.sh solution     # (option) rejoue la solution de référence
```

Sans second projet, `verify.sh` signale que le partage n'a pas pu être vérifié de bout en bout (`○`) : faites-le constater en binôme.

---

## 💡 Indices

<details>
<summary><code>podman login</code> échoue : <code>x509: certificate signed by unknown authority</code></summary>

Le certificat du routeur n'est pas reconnu par votre poste. Sur un cluster de test : `--tls-verify=false` (à `login` et à `push`). Jamais en production.
</details>

<details>
<summary><code>podman push</code> : <code>unauthorized</code> ou <code>denied</code></summary>

Le jeton a expiré entre `oc login` et `podman login`, ou le chemin ne commence pas par le nom de votre projet.
</details>

<details>
<summary>L'étiquette <code>1.1</code> reste vide après <code>oc apply</code></summary>

L'import a échoué : `oc describe imagestream api` en donne la raison (registre injoignable depuis le cluster, limite de débit de Docker Hub). `oc import-image api:1.1` relance l'import.
</details>

<details>
<summary>Le pod du second projet reste en <code>ImagePullBackOff</code> après <code>partager.sh</code></summary>

Le droit a été donné dans le mauvais projet. Contrôlez : `oc policy who-can get imagestreams/layers -n <projet des images>` doit citer `system:serviceaccount:<second projet>:default`.
</details>

## 🚀 Pour aller plus loin

- Donnez le droit à **tous** les comptes de service du second projet : `oc policy add-role-to-group system:image-puller system:serviceaccounts:<projet>`.
- Posez un déclencheur : `oc set triggers deployment/essai --from-image=api:prod -c telemarche-api`, puis `oc tag api:1.1 api:prod` après avoir fait pointer `1.1` ailleurs. Que se passe-t-il ?
- Copiez l'image vers un autre registre sans la télécharger : `oc image mirror --help`.
