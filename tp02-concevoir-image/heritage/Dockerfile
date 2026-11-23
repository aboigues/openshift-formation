# L'image « historique » de l'API de Télémarché, écrite il y a quelques années
# pour un serveur Docker. Elle fonctionne avec « podman run »… et pas sur OpenShift.
#
# NE LA CORRIGEZ PAS ICI : lisez-la, faites-la échouer, puis réécrivez-la dans
# starter/Dockerfile.
FROM registry.access.redhat.com/ubi10/go-toolset:10.3
USER root
WORKDIR /app
COPY . .
# Envoyé depuis Windows, le script arrive sans droit d'exécution : on le lui donne.
RUN chmod 755 /app/demarrer.sh
RUN go build -o /app/api ./cmd/api
RUN mkdir /app/journal
ENV PORT=80
ENV JOURNAL_DIR=/app/journal
EXPOSE 80
ENTRYPOINT /app/demarrer.sh
