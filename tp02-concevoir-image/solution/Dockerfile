# L'image de l'API de Télémarché, réécrite pour OpenShift.
#
#   podman build -f starter/Dockerfile -t telemarche-api:dev ../apps/telemarche
#   podman run --rm --user 12345:0 -p 8080:8080 telemarche-api:dev      # comme sur OpenShift

# --- Étape 1 : compiler. Rien de cette étape n'est livré.
FROM registry.access.redhat.com/ubi10/go-toolset:10.3 AS build
WORKDIR /opt/app-root/src
# Les dépendances d'abord : elles changent rarement, la couche reste en cache.
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
ARG APP_VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X main.version=${APP_VERSION}" -o /tmp/api ./cmd/api

# --- Étape 2 : exécuter. Une image minimale, et seulement le binaire.
FROM registry.access.redhat.com/ubi10/ubi-micro:10.3
LABEL name="telemarche-api" \
      io.k8s.display-name="Télémarché API" \
      io.k8s.description="API catalogue et commandes de Télémarché" \
      io.openshift.expose-services="8080:http" \
      io.openshift.tags="go,api,telemarche"
COPY --from=build --chown=1001:0 /tmp/api /app/api
# Le seul répertoire où l'application écrit. OpenShift choisit l'UID, mais le
# groupe est toujours 0 : on donne au groupe 0 les droits du propriétaire.
# À faire AVANT « USER » : après, on n'est plus root et chgrp échoue.
RUN mkdir -p /app/journal \
 && chgrp -R 0 /app/journal \
 && chmod -R g=u /app/journal
# Des valeurs par défaut, que le déploiement peut remplacer. Un port supérieur
# à 1024 : en dessous, il faut des privilèges.
ENV PORT=8080 \
    LOG_LEVEL=info \
    JOURNAL_DIR=/app/journal
# Un UID numérique, différent de 0 : pour les plateformes autres qu'OpenShift.
USER 1001
EXPOSE 8080
# Forme exec : l'application est le processus n° 1 et reçoit SIGTERM.
ENTRYPOINT ["/app/api"]
