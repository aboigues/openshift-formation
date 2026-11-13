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
# TODO 6 : le rôle qui permet de TIRER les images d'un projet
oc policy add-role-to-user ______ \
  "system:serviceaccount:${CONSOMMATEUR}:______" \
  -n "______"
# TODO 7 (ci-dessus) : le compte de service des pods, puis le projet où se donne le droit :
#          "${IMAGES}" ou "${CONSOMMATEUR}" ?

oc policy who-can get imagestreams/layers -n "${IMAGES}" | grep "${CONSOMMATEUR}"
