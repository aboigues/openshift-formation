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

Les TP se jouent sur **OKD 5.0**, la distribution communautaire d'OpenShift, lancée par CRC sur chaque poste (AlmaLinux, 64 Go) : installation et réglages dans [docs/environnements.md](docs/environnements.md). `verify.sh` s'adapte à vos droits sur le cluster : projet jetable si vous pouvez en créer, votre projet courant sinon.

## Le fil rouge : Télémarché

La boutique en ligne de Telemach : une vitrine **web**, une **api**, et sa base **db** (TP06). Sources et documentation : [`apps/telemarche`](apps/telemarche/README.md). À partir du TP08, la caisse des magasins la rejoint : [`apps/telecaisse`](apps/telecaisse/README.md).

## Les TP

| TP | Module | Sujet | Statut |
|----|--------|-------|--------|
| [TP01](tp01-deployer-gerer/) | 1 | Déployer et gérer : `oc new-app`, Route HTTPS, configuration, mise à jour, conversion d'une DeploymentConfig | validé ¹ |
| [TP02](tp02-concevoir-image/) | 2 | Concevoir une image : UID arbitraire, groupe 0, étapes multiples, arrêt propre | validé ¹ ² |
| [TP03](tp03-registre-droits/) | 3 | Registre et droits : ImageStream, promotion, partage entre projets, registre externe | validé ¹ |
| [TP04](tp04-build-hooks/) | 4 | Builds : BuildConfig, déclencheurs, build binaire, hook post-commit | validé ¹ ² |
| [TP05](tp05-personnaliser-s2i/) | 5 | Source-to-Image : scripts dans le dépôt, image de construction sur mesure | validé ¹ ² |
| [TP06](tp06-modele-multi-conteneurs/) | 6 | Modèle à plusieurs conteneurs : Template, paramètres générés, PostgreSQL persistant, conteneur d'initialisation | validé ¹ ² |
| [TP07](tp07-sante-strategies/) | 7 | Santé et stratégies : sondes de démarrage, de disponibilité et de vie, mise à jour sans coupure, PodDisruptionBudget, canari par la Route | validé ¹ ² |
| [TP08](tp08-integrer-migrer/) | 8 | Intégrer et migrer : Télécaisse (Jakarta EE) construite par `wildfly-s2i`, base restée dans le SI (`ExternalName`), Secret, appel à Télémarché | validé ¹ ² |

¹ `verify.sh solution` rejoué avec succès sur CRC 2.65 / OKD 5.0, sous l'utilisateur `developer`, le 23 novembre 2026 (`./scripts/test-all.sh`).
² Ce qui se prouve sans cluster (images sous UID arbitraire, prémisses des TP) est rejoué par la CI, job `images`.

## Les barrières

| Barrière | Commande | Cluster |
|---|---|---|
| Contrôles statiques | `./scripts/lint.sh` | non |
| Sécurité : secrets, manifestes, code Go, images | `./scripts/securite.sh` | non |
| Images et prémisses | job `images` de la CI | non |
| Tous les TP | `./scripts/test-all.sh` | oui |
| Tous les TP, avant chaque fusion : check `okd` ([mise en place](docs/gate-okd.md)) | workflow `okd.yml`, runner sur le poste CRC | oui |

OpenShift est une marque de Red Hat ; OKD est son projet communautaire. Cette formation est indépendante de l'éditeur.
