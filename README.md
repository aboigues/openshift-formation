# Formation OpenShift — Travaux pratiques

![TP — vérification](https://github.com/aboigues/openshift-formation/actions/workflows/ci.yml/badge.svg)

> Une formation [**Telemach Learning**](https://www.telemach-learning.fr) : **DEVOPS-020 — OpenShift : développer et déployer des applications conteneurisées** (3 jours).
> Le cours est dans les supports. **Ce dépôt contient uniquement les TP.**

## Comment fonctionnent les TP

```
tpNN-theme/
├── README.md      ← le guide pas à pas (commencez TOUJOURS par là)
├── starter/       ← les fichiers À COMPLÉTER (cherchez les « ______ » et les « # TODO »)
├── solution/      ← la solution de référence (en dernier recours)
└── verify.sh      ← le contrôle automatique de l'objectif
```

1. Lisez le `README.md` du TP en entier.
2. Travaillez dans `starter/`.
3. Validez : `./verify.sh` (votre travail) ; `./verify.sh solution` montre le résultat attendu.

`verify.sh` s'adapte à vos droits sur le cluster : projet jetable si vous pouvez en créer, votre projet courant sinon. Voir [docs/environnements.md](docs/environnements.md).

## Le fil rouge : Télémarché

La boutique en ligne de Telemach : une vitrine **web**, une **api**, et bientôt une base **db**. Sources et documentation : [`apps/telemarche`](apps/telemarche/README.md).

## Les TP

| TP | Module | Sujet | Statut |
|----|--------|-------|--------|
| [TP01](tp01-deployer-gerer/) | 1 | Déployer et gérer : `oc new-app`, Route HTTPS, configuration, mise à jour, conversion d'une DeploymentConfig | écrit ¹ |
| [TP02](tp02-concevoir-image/) | 2 | Concevoir une image : UID arbitraire, groupe 0, étapes multiples, arrêt propre | écrit ¹ ² |
| [TP03](tp03-registre-droits/) | 3 | Registre et droits : ImageStream, promotion, partage entre projets, registre externe | écrit ¹ |
| [TP04](tp04-build-hooks/) | 4 | Builds : BuildConfig, déclencheurs, build binaire, hook post-commit | écrit ¹ ² |
| [TP05](tp05-personnaliser-s2i/) | 5 | Source-to-Image : scripts dans le dépôt, image de construction sur mesure | écrit ¹ ² |
| TP06 | 6 | Modèle à plusieurs conteneurs | à venir |
| TP07 | 7 | Santé et stratégies de déploiement | à venir |
| TP08 | 8 | Intégrer et migrer (Télécaisse, WildFly) | à venir |

¹ `verify.sh` n'a pas encore été rejoué sur un cluster OpenShift.
² Ce qui se prouve sans cluster (images sous UID arbitraire, prémisses des TP) est rejoué par la CI, job `images`.

## Les barrières

| Barrière | Commande | Cluster |
|---|---|---|
| Contrôles statiques | `./scripts/lint.sh` | non |
| Images et prémisses | job `images` de la CI | non |
| Tous les TP | `./scripts/test-all.sh` | oui |

OpenShift est une marque de Red Hat. Cette formation est indépendante de l'éditeur.
