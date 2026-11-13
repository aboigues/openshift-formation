#!/usr/bin/env bash
# TP02 — votre Dockerfile est construit DANS le cluster, puis l'image est
# déployée telle quelle : elle doit démarrer sous la contrainte restricted-v2
# (UID arbitraire, groupe 0), écrire son journal, et s'arrêter proprement.
#
# HERITAGE=1 ./verify.sh solution : contrôle en plus que l'image historique
# échoue bien sur ce cluster (la prémisse du TP ; utile au formateur).
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

step "Le Dockerfile ($(basename "$DIR"))"
no_holes "$DIR"
check "Deux étapes au moins (FROM … AS …)" bash -c "[ \"\$(grep -ciE '^FROM ' '$DIR/Dockerfile')\" -ge 2 ]"
check "Aucune étiquette « latest »" bash -c "! grep -iE '^FROM .*(:latest( |\$)|/[^:@ ]+( |\$))' '$DIR/Dockerfile'"
need_cluster
verify_project tp02-verify

# construire NOM DOSSIER : build binaire de stratégie Docker, sources + Dockerfile.
construire() {
  copie_sources telemarche
  cp -R "$2/." "$TMP/"
  o new-build --name="$1" --binary --strategy=docker -n "$NS" \
    --labels="app=$1,app.kubernetes.io/part-of=telemarche" >/dev/null
  build_dir "$1" "$TMP"
}

# deployer NOM PORT : un Deployment qui suit l'étiquette NOM:latest, et son Service.
deployer() {
  o apply -n "$NS" -f - >/dev/null <<FIN
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $1
  labels: {app: $1, app.kubernetes.io/part-of: telemarche}
  annotations:
    image.openshift.io/triggers: >-
      [{"from":{"kind":"ImageStreamTag","name":"$1:latest"},"fieldPath":"spec.template.spec.containers[?(@.name==\"api\")].image"}]
spec:
  replicas: 1
  selector:
    matchLabels: {app: $1}
  template:
    metadata:
      labels: {app: $1, app.kubernetes.io/part-of: telemarche}
    spec:
      containers:
        - name: api
          image: $1:latest
          ports:
            - containerPort: $2
          resources:
            requests: {cpu: 50m, memory: 32Mi}
            limits: {memory: 128Mi}
---
apiVersion: v1
kind: Service
metadata:
  name: $1
  labels: {app: $1, app.kubernetes.io/part-of: telemarche}
spec:
  selector: {app: $1}
  ports:
    - name: http
      port: 8080
      targetPort: $2
FIN
}

step "La construction, dans le cluster"
construire api "$DIR"
build_reussi "L'image se construit" "$BUILD" 900
META='{.image.dockerImageMetadata.Config'
assert_match "USER numérique, différent de 0" '^[1-9][0-9]*(:[0-9]+)?$' "$(jp imagestreamtag/api:latest "$META.User}")"
assert_contains "Le port déclaré est 8080" "8080/tcp" "$(jp imagestreamtag/api:latest "$META.ExposedPorts}")"
assert_eq "Label io.openshift.expose-services" "8080:http" "$(jp imagestreamtag/api:latest "$META.Labels.io\.openshift\.expose-services}")"
TAILLE="$(jp imagestreamtag/api:latest '{.image.dockerImageMetadata.Size}')"
info "Taille de l'image : $(( ${TAILLE:-0} / 1024 / 1024 )) Mo"
check "Image finale légère : ni compilateur ni sources (moins de 150 Mo)" test "${TAILLE:-999999999}" -lt 157286400

step "Le démarrage sur OpenShift, sans aucun droit supplémentaire"
deployer api 8080
wait_rollout api 240
POD="$(o get pods -n "$NS" -l app=api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
assert_eq "Contrainte de sécurité appliquée : restricted-v2" "restricted-v2" "$(jp "pod/$POD" '{.metadata.annotations.openshift\.io/scc}')"
assert_match "UID imposé par le projet, inconnu de l'image" '^[0-9]{6,}$' "$(jp "pod/$POD" '{.spec.containers[0].securityContext.runAsUser}')"
wait_svc_http api 8080 /version 90 || true
assert_contains "Le journal des commandes est ouvert en écriture (groupe 0, g=u)" "journal des commandes ouvert" \
  "$(o logs "pod/$POD" -n "$NS" 2>/dev/null || true)"

step "L'arrêt propre"
DEBUT=$SECONDS
o delete pod "$POD" -n "$NS" --wait=true --timeout=60s >/dev/null 2>&1 || true
DUREE=$((SECONDS - DEBUT))
info "Pod arrêté en ${DUREE} s"
check "L'application reçoit SIGTERM et s'arrête d'elle-même (moins de 20 s, pas de SIGKILL à 30 s)" test "$DUREE" -lt 20

if [ "${HERITAGE:-0}" = "1" ]; then
  step "La prémisse : l'image historique échoue sur ce cluster"
  construire api-heritage "$HERE/heritage"
  build_reussi "L'image historique se construit" "$BUILD" 900
  deployer api-heritage 80
  i=0; JOURNAL=""
  while [ "$i" -lt 120 ]; do
    JOURNAL="$(o logs deployment/api-heritage -n "$NS" 2>/dev/null || true)"
    printf '%s' "$JOURNAL" | grep -q "permission denied" && break
    sleep 5; i=$((i+5))
  done
  assert_contains "Elle s'arrête sur « permission denied »" "permission denied" "$JOURNAL"
  assert_eq "Aucun pod de l'image historique n'est prêt" "" "$(jp deployment/api-heritage '{.status.readyReplicas}')"
fi

summary
