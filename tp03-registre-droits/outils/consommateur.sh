#!/usr/bin/env bash
# Déploie, dans le projet consommateur, l'image « api:prod » du projet des images.
#
#   ./outils/consommateur.sh <projet des images> <projet consommateur>
#
# L'image est désignée par l'adresse INTERNE du registre :
#   image-registry.openshift-image-registry.svc:5000/<projet>/<image>:<étiquette>
set -euo pipefail
IMAGES="${1:?Usage : ./outils/consommateur.sh <projet des images> <projet consommateur>}"
CONSOMMATEUR="${2:?Usage : ./outils/consommateur.sh <projet des images> <projet consommateur>}"

oc apply -n "$CONSOMMATEUR" -f - <<FIN
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  labels: {app: api, app.kubernetes.io/part-of: telemarche}
spec:
  replicas: 1
  selector:
    matchLabels: {app: api}
  template:
    metadata:
      labels: {app: api, app.kubernetes.io/part-of: telemarche}
    spec:
      containers:
        - name: api
          image: image-registry.openshift-image-registry.svc:5000/${IMAGES}/api:prod
          ports:
            - containerPort: 8080
          resources:
            requests: {cpu: 50m, memory: 32Mi}
            limits: {memory: 64Mi}
FIN
