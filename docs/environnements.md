# Environnements et réglages

Les sessions se jouent sur **OKD 5.0**, la distribution communautaire d'OpenShift, que chaque stagiaire lance sur son poste avec **CRC** (préréglage `okd`). Aucune souscription Red Hat n'est nécessaire.

Les TP restent valables sur tout OKD ou OpenShift auquel `oc` est connecté : seuls vos droits changent, et `verify.sh` s'y adapte.

## Le poste

| Besoin | Valeur |
|---|---|
| Processeur | x86_64 avec virtualisation matérielle. **Pas d'arm64** : OKD n'y est pas publié, donc pas de Mac Apple Silicon |
| Système | Linux (libvirt), Windows (Hyper-V) ou macOS Intel |
| Mémoire | 16 Go au minimum ; la machine virtuelle en prend 14 |
| Disque | 60 Go libres |

| Outil | Rôle | Obligatoire |
|---|---|---|
| `crc` (2.65 ou plus récent) | lance OKD | oui |
| `oc` (5.0) | tout ; `crc oc-env` fournit celui du cluster | oui |
| `git`, `curl`, `tar`, `bash` | `verify.sh` | oui |
| `podman` ou `docker` | essais locaux des TP02, TP03 et TP05 | non : le cluster construit |

## Lancer OKD avec CRC

`crc` se télécharge sans compte Red Hat : <https://developers.redhat.com/content-gateway/rest/mirror2/pub/openshift-v4/clients/crc/latest/>.

```bash
crc config set preset okd          # avant le premier « crc setup »
crc config set cpus 4
crc config set memory 14336        # en Mio ; 10752 par défaut, juste pour les builds des TP
crc config set disk-size 50        # en Gio ; 31 par défaut
crc setup
crc start                          # 15 à 30 minutes la première fois
eval "$(crc oc-env)"               # met le oc du cluster dans le PATH
crc console --credentials          # identifiants de developer et de kubeadmin
oc login -u developer https://api.crc.testing:6443
```

Le préréglage ne change qu'à la création : sur une instance existante, `crc delete`, puis `crc setup` et `crc start`.

L'utilisateur `developer` crée ses propres projets : `verify.sh` travaille donc dans un projet jetable. Travaillez sous `developer`, pas sous `kubeadmin` : les TP montrent ce qu'un développeur peut faire.

Ces réglages ont suffi à rejouer les huit TP (CRC 2.65, OKD 5.0, le 23 novembre 2026). Hyper-V exige que les 14 Go soient **libres** au démarrage de la machine virtuelle : fermez Docker Desktop et les applications gourmandes, et plafonnez WSL (ci-dessous).

### Sous Windows

- CRC publie l'API sur `127.0.0.1:6443` et le routeur sur les ports 80 et 443 de Windows. Chaque Route créée est ajoutée au fichier `hosts` de Windows : le navigateur l'ouvre directement.
- Depuis WSL, en réseau NAT (le défaut), ni `api.crc.testing` ni les Routes ne sont joignables. Les TP y ont été rejoués avec deux contournements : le `oc.exe` de CRC (`%USERPROFILE%\.crc\bin\oc`) appelé depuis WSL, et `curl` envoyant les noms `*.apps-crc.testing` vers l'adresse de Windows. Le réseau « miroir » de WSL, où `127.0.0.1` désigne Windows, les remplace : c'est la configuration du runner de la gate `okd` ([gate-okd.md](gate-okd.md), étape 1, qui ajoute aussi les noms de CRC à `/etc/hosts`). Dans `%USERPROFILE%\.wslconfig`, puis `wsl --shutdown` :

  ```ini
  [wsl2]
  memory=6GB
  networkingMode=mirrored
  dnsTunneling=true
  ```

- Un build envoyé depuis Windows (`oc start-build --from-dir`) perd le droit d'exécution des fichiers. Les TP en tiennent compte : S2I le rend aux scripts `.s2i/bin`, et l'image historique du TP02 le pose elle-même.

## Avant le premier TP : contrôler le cluster

```bash
oc version                                                   # serveur 5.0
oc api-resources --api-group=build.openshift.io              # builds et BuildConfigs (TP04, TP05)
oc api-resources --api-group=image.openshift.io              # ImageStreams (TP03 à TP05)
oc api-resources --api-group=apps.openshift.io               # DeploymentConfig (TP01, étape 7)
oc auth can-i create builds.build.openshift.io --subresource=docker
```

Les builds, les DeploymentConfig et le registre intégré sont des fonctionnalités optionnelles d'OKD, qu'un administrateur peut désactiver à l'installation. Si `apps.openshift.io` manque, le TP01 l'indique à l'étape 7. Si les builds manquent, les TP02 à TP05 ne se feront pas sur ce cluster.

## Où travaille `verify.sh`

| Vos droits | Ce que fait `verify.sh` |
|---|---|
| Vous pouvez créer des projets (CRC, cas des sessions) | un projet jetable `tpNN-verify-<vous>`, supprimé à la fin ; votre projet de travail n'est jamais touché |
| Vous ne le pouvez pas (cluster partagé, d'entreprise) | il travaille **dans votre projet courant** : les objets des TP y sont supprimés puis recréés, après confirmation |

| Variable | Effet |
|---|---|
| `KEEP=1` | garde le projet jetable après la vérification, pour l'inspecter |
| `OUI=1` | confirme d'avance la vérification dans le projet courant |
| `PROJET_VERIF=<projet>` | un projet existant, à utiliser pour la vérification |
| `PROJET_2=<projet>` | un second projet existant (TP03) |
| `PROJET_JETABLE=0` | n'essaie pas de créer de projet |
| `DEPOT_GIT=<adresse>`, `REF_GIT=<branche>` | le dépôt que clonent les builds, au lieu de votre copie de travail |
| `HERITAGE=1` | TP02 : contrôle aussi que l'image historique échoue sur ce cluster |
| `ROUTEUR=<adresse>` | envoie les requêtes vers les Routes à cette adresse, sans passer par le DNS ; par exemple `ROUTEUR=127.0.0.1` depuis WSL avec CRC |

Par défaut, les builds de `verify.sh` clonent **votre copie de travail**, servie par un petit dépôt Git lancé dans le projet de vérification (`depot-git`) : ils ne dépendent ni de GitHub, ni de ce qui y est publié.

## Ce que le cluster doit permettre

- créer des Deployments, des Routes, des ImageStreams et des BuildConfigs dans son projet (rôle `admin` ou `edit`) ;
- lancer des builds de stratégie **Docker** et **Source** ;
- sortir vers `registry.access.redhat.com`, `docker.io` et `quay.io` (PostgreSQL et WildFly, TP06 et TP08), ainsi que `repo1.maven.org` (build Maven du TP08). Ces images se tirent sans compte : un OKD n'a pas de clé d'accès à `registry.redhat.io`, et les TP ne s'en servent pas ;
- environ 4 Go de mémoire et 2 processeurs de quota par projet. Le build WildFly du TP08 prend à lui seul jusqu'à 1,5 Go.

Docker Hub limite les téléchargements anonymes **par adresse IP**. Dans une salle où tous les postes sortent par la même adresse, faites tirer les images `telemachlearning/*` une fois par poste avant la session, ou prévoyez un miroir.

## Tout rejouer avant une session

```bash
oc login …
./scripts/lint.sh          # sans cluster
./scripts/test-all.sh      # verify.sh solution de chaque TP, sur le cluster connecté
```

Dans GitHub, le check `okd` fait la même chose sur le CRC d'un poste, avant chaque fusion d'une PR qui touche les TP : voir [gate-okd.md](gate-okd.md).
