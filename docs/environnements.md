# Environnements et réglages

Les TP tournent sur n'importe quel OpenShift 4 auquel `oc` est connecté. Seuls vos droits changent, et `verify.sh` s'y adapte.

## Outils du poste

| Outil | Rôle | Obligatoire |
|---|---|---|
| `oc` (4.22 ou proche) | tout | oui |
| `git`, `curl`, `tar`, `bash` | `verify.sh` | oui |
| `podman` ou `docker` | essais locaux des TP02, TP03 et TP05 | non : le cluster construit |

## Où travaille `verify.sh`

| Vos droits | Ce que fait `verify.sh` |
|---|---|
| Vous pouvez créer des projets (OpenShift Local, cluster personnel) | un projet jetable `tpNN-verify-<vous>`, supprimé à la fin ; votre projet de travail n'est jamais touché |
| Vous ne le pouvez pas (Developer Sandbox, cluster d'entreprise) | il travaille **dans votre projet courant** : les objets des TP y sont supprimés puis recréés, après confirmation |

| Variable | Effet |
|---|---|
| `KEEP=1` | garde le projet jetable après la vérification, pour l'inspecter |
| `OUI=1` | confirme d'avance la vérification dans le projet courant |
| `PROJET_VERIF=<projet>` | un projet existant, à utiliser pour la vérification |
| `PROJET_2=<projet>` | un second projet existant (TP03) |
| `PROJET_JETABLE=0` | n'essaie pas de créer de projet |
| `DEPOT_GIT=<adresse>`, `REF_GIT=<branche>` | le dépôt que clonent les builds, au lieu de votre copie de travail |
| `HERITAGE=1` | TP02 : contrôle aussi que l'image historique échoue sur ce cluster |

Par défaut, les builds de `verify.sh` clonent **votre copie de travail**, servie par un petit dépôt Git lancé dans le projet de vérification (`depot-git`) : ils ne dépendent ni de GitHub, ni de ce qui y est publié.

## Ce que le cluster doit permettre

- créer des Deployments, des Routes, des ImageStreams et des BuildConfigs dans son projet (rôle `admin` ou `edit`) ;
- lancer des builds de stratégie **Docker** et **Source** (`oc auth can-i create builds.build.openshift.io --subresource=docker`) ;
- sortir vers `registry.access.redhat.com` et `docker.io` ;
- environ 4 Go de mémoire et 2 processeurs de quota par projet.

## Tout rejouer avant une session

```bash
oc login …
./scripts/lint.sh          # sans cluster
./scripts/test-all.sh      # verify.sh solution de chaque TP, sur le cluster connecté
```

Dans la CI, le job `cluster` fait la même chose dès que le dépôt GitHub porte les secrets `OPENSHIFT_SERVER` et `OPENSHIFT_TOKEN`.
