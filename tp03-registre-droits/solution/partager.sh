#!/usr/bin/env bash
# Ouvre les images d'un projet aux pods d'un autre projet.
#
#   ./partager.sh <projet des images> <projet consommateur>
#
# Le droit se donne DANS le projet qui possède les images, AU compte de service
# qui les consomme.
set -euo pipefail
IMAGES="${1:?Usage : ./partager.sh <projet des images> <projet consommateur>}"
CONSOMMATEUR="${2:?Usage : ./partager.sh <projet des images> <projet consommateur>}"

# « default » est le compte de service sous lequel tournent les pods d'un projet.
oc policy add-role-to-user system:image-puller \
  "system:serviceaccount:${CONSOMMATEUR}:default" \
  -n "${IMAGES}"

oc policy who-can get imagestreams/layers -n "${IMAGES}" | grep "${CONSOMMATEUR}"
