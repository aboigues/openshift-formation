# L'image de l'API de Télémarché, réécrite pour OpenShift.
#
#   podman build -f starter/Dockerfile -t telemarche-api:dev ../apps/telemarche
#   podman run --rm --user 12345:0 -p 8080:8080 telemarche-api:dev      # comme sur OpenShift

# --- Étape 1 : compiler. Rien de cette étape n'est livré.
FROM registry.access.redhat.com/ubi10/go-toolset:10.3 AS ______      # TODO 1 : nommer l'étape, pour s'y référer plus bas
WORKDIR /opt/app-root/src
# Les dépendances d'abord : elles changent rarement, la couche reste en cache.
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
ARG APP_VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X main.version=${APP_VERSION}" -o /tmp/api ./cmd/api

# --- Étape 2 : exécuter. Une image minimale, et seulement le binaire.
# TODO 2 : l'image UBI la plus petite, sans gestionnaire de paquets (version 10.3)
FROM registry.access.redhat.com/ubi10/______
LABEL name="telemarche-api" \
      io.k8s.display-name="Télémarché API" \
      io.k8s.description="API catalogue et commandes de Télémarché" \
      io.openshift.expose-services="8080:http" \
      io.openshift.tags="go,api,telemarche"
# TODO 3 : copier le binaire depuis l'étape de compilation ; propriétaire 1001, groupe 0
COPY --from=______ --chown=______ /tmp/api /app/api
# Le seul répertoire où l'application écrit. OpenShift choisit l'UID, mais le
# groupe est toujours 0 : on donne au groupe 0 les droits du propriétaire.
# À faire AVANT « USER » : après, on n'est plus root et chgrp échoue.
RUN mkdir -p /app/journal \
 && chgrp -R ______ /app/journal \
 && chmod -R ______ /app/journal
# TODO 4 (ci-dessus) : le groupe imposé par OpenShift, puis « le groupe reçoit les droits du propriétaire »
# Des valeurs par défaut, que le déploiement peut remplacer. Un port supérieur
# à 1024 : en dessous, il faut des privilèges.                      TODO 5 : PORT
ENV PORT=______ \
    LOG_LEVEL=info \
    JOURNAL_DIR=/app/journal
# Un UID numérique, différent de 0 : pour les plateformes autres qu'OpenShift.
USER ______                        # TODO 6
EXPOSE ______                      # TODO 7
# Forme exec : l'application est le processus n° 1 et reçoit SIGTERM.
ENTRYPOINT ______                  # TODO 8 : lancer /app/api, en forme exec
