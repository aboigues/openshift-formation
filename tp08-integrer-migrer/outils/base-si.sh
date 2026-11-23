#!/usr/bin/env bash
# La base de la caisse, telle qu'elle existe dans le système d'information de
# Telemach. Pour le TP, on la simule dans un projet à part, qui joue le rôle
# du « dehors » : Télécaisse s'y connectera par un nom DNS, comme à une base
# hors du cluster.
#   ./outils/base-si.sh [projet]       # par défaut : <vous>-si, créé s'il le faut
# Affiche à la fin l'adresse de la base et ses identifiants.
source "$(cd "$(dirname "$0")/../.." && pwd)/scripts/lib.sh"
need_cluster

PROJET="${1:-}"
if [ -z "$PROJET" ]; then
  if peut_creer_projet; then
    PROJET="$(suffixe)-si"
    o get project "$PROJET" >/dev/null 2>&1 || o new-project "$PROJET" --skip-config-write >/dev/null \
      || die "Création du projet $PROJET impossible."
  else
    PROJET="$(o project -q)"
    warn "Pas de création de projet possible : la base « du SI » va dans votre projet ($PROJET)."
  fi
fi
IMAGE_PG="${IMAGE_PG:-quay.io/sclorg/postgresql-18-c10s:20261118}"

step "La base de la caisse dans le projet $PROJET"
if ! o get secret si-caisse -n "$PROJET" >/dev/null 2>&1; then
  o create secret generic si-caisse -n "$PROJET" \
    --from-literal=POSTGRESQL_USER=caisse \
    --from-literal=POSTGRESQL_PASSWORD="$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16)" \
    --from-literal=POSTGRESQL_DATABASE=caisse >/dev/null
  o label secret si-caisse -n "$PROJET" app.kubernetes.io/part-of=telecaisse >/dev/null
fi
o apply -n "$PROJET" -f - >/dev/null <<FIN
apiVersion: apps/v1
kind: Deployment
metadata:
  name: si-caisse
  labels: {app: si-caisse, app.kubernetes.io/part-of: telecaisse}
spec:
  replicas: 1
  strategy: {type: Recreate}
  selector:
    matchLabels: {app: si-caisse}
  template:
    metadata:
      labels: {app: si-caisse, app.kubernetes.io/part-of: telecaisse}
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: postgresql
          image: ${IMAGE_PG}
          envFrom:
            - secretRef: {name: si-caisse}
          ports:
            - containerPort: 5432
          readinessProbe:
            exec: {command: ["/usr/libexec/check-container"]}
            periodSeconds: 5
            timeoutSeconds: 5
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits: {memory: 256Mi}
---
apiVersion: v1
kind: Service
metadata:
  name: si-caisse
  labels: {app: si-caisse, app.kubernetes.io/part-of: telecaisse}
spec:
  selector: {app: si-caisse}
  ports:
    - port: 5432
      targetPort: 5432
FIN
o rollout status deployment/si-caisse -n "$PROJET" --timeout=300s >/dev/null || die "La base ne démarre pas : oc get pods -n $PROJET"
o exec -i -n "$PROJET" deployment/si-caisse -- psql -q -U caisse -d caisse < "$RACINE/apps/telecaisse/sql/schema.sql" \
  || die "Chargement du schéma impossible."
info "Base prête, historique chargé."

lire() { o get secret si-caisse -n "$PROJET" -o "jsonpath={.data.$1}" | base64 -d; }
echo
echo "  Adresse : si-caisse.${PROJET}.svc.cluster.local (port 5432)"
echo "  Pour créer le Secret de Télécaisse, dans VOTRE projet :"
echo "    oc create secret generic telecaisse-db \\"
echo "      --from-literal=POSTGRESQL_USER=$(lire POSTGRESQL_USER) \\"
echo "      --from-literal=POSTGRESQL_PASSWORD=$(lire POSTGRESQL_PASSWORD) \\"
echo "      --from-literal=POSTGRESQL_DATABASE=$(lire POSTGRESQL_DATABASE)"
