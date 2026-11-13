# Télémarché — l'application fil rouge

| Composant | Programme | Port | Dockerfile |
|---|---|---|---|
| **api** : catalogue et commandes | `cmd/api` | 8080 | `Dockerfile.api` |
| **web** : la vitrine, relaie `/api/` vers l'API | `cmd/web` | 8080 | `Dockerfile.web` |

`Dockerfile` construit l'un ou l'autre (`--build-arg COMPOSANT=web`, `api` par défaut). Les images publiées (`docker.io/telemachlearning/telemarche-api` et `-web`, versions `1.0` et `1.1`) servent au TP01 ; à partir du TP02, les images sont construites depuis ce dossier.

## L'API

| Chemin | Rôle |
|---|---|
| `GET /healthz` | vivant ; ne dépend jamais de la base |
| `GET /ready` | prêt : démarré, pas en cours d'arrêt, stockage joignable |
| `GET /version`, `GET /api/info` | version, pod, mode de stockage |
| `GET /api/products`, `GET`/`POST /api/orders` | le catalogue et les commandes |
| `GET /metrics` | métriques Prometheus |

| Variable | Défaut | Effet |
|---|---|---|
| `PORT` | `8080` | port d'écoute |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error` ; toute autre valeur arrête le programme |
| `DB_HOST` | *(vide)* | vide : stockage en mémoire ; renseigné : PostgreSQL |
| `DB_USER`, `DB_PASSWORD`, `DB_NAME` | | acceptés aussi sous les noms `POSTGRESQL_*` et `POSTGRES_*` |
| `JOURNAL_DIR` | *(vide)* | répertoire d'un journal des commandes ; s'il n'est pas inscriptible, le programme s'arrête (TP02) |
| `STARTUP_SECONDS`, `SHUTDOWN_SECONDS` | `3`, `5` | démarrage simulé, délai de vidange après `SIGTERM` |

- `/app/api --self-test` contrôle la version et le catalogue embarqué (`cmd/api/catalogue.json`), sans rien écouter : code 0 ou 1. C'est le contrôle du hook post-commit (TP04).
- `/app/migrate` crée le schéma et le catalogue de départ dans PostgreSQL, puis se termine.

## La vitrine

`PORT` (8080), `API_URL` (`http://api`), `LOG_LEVEL`. Points d'entrée : `/`, `/healthz`, `/ready`, `/version`, et `/api/…` relayé.
