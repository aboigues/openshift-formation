# Télémarché — une recette pour les deux composants (principe DRY).
#
#   podman build --build-arg COMPOSANT=api --build-arg APP_VERSION=1.0 -t telemarche-api:1.0 .
#   podman build --build-arg COMPOSANT=web --build-arg APP_VERSION=1.0 -t telemarche-web:1.0 .
#
# Sans argument, c'est l'API qui est construite : « oc new-build --strategy=docker »
# sur ce dossier fonctionne donc tel quel.
#
# Dockerfile.api et Dockerfile.web sont les mêmes recettes, écrites pour un seul
# composant : ce sont elles que les supports de cours détaillent.
FROM registry.access.redhat.com/ubi10/go-toolset:10.3 AS build
WORKDIR /opt/app-root/src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
# COMPOSANT : api ou web. APP_VERSION et non VERSION : go-toolset définit déjà
# une variable d'environnement VERSION, qui l'emporterait sur l'argument.
ARG COMPOSANT=api
ARG APP_VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X main.version=${APP_VERSION}" -o /tmp/app "./cmd/${COMPOSANT}"

FROM registry.access.redhat.com/ubi10/ubi-micro:10.3
LABEL io.k8s.display-name="Télémarché" \
      io.k8s.description="Composant de Télémarché, la boutique de démonstration de Telemach" \
      io.openshift.expose-services="8080:http" \
      io.openshift.tags="go,telemarche" \
      org.opencontainers.image.source="https://github.com/aboigues/openshift-formation"
# Le même binaire sous deux noms : /app/migrate crée le schéma de la base (API).
COPY --from=build --chown=1001:0 /tmp/app /app/app
COPY --from=build --chown=1001:0 /tmp/app /app/migrate
ENV PORT=8080 LOG_LEVEL=info
USER 1001
EXPOSE 8080
ENTRYPOINT ["/app/app"]
