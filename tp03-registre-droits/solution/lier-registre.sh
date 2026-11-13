#!/usr/bin/env bash
# Donne à un projet les identifiants d'un registre externe privé.
#
#   ./lier-registre.sh <projet> <serveur> <compte> <jeton>
#   ./lier-registre.sh "$(oc project -q)" quay.io telemach+lecture 'le-jeton-du-robot'
#
# Les identifiants passent en arguments : ils ne sont écrits dans aucun fichier.
set -euo pipefail
USAGE="Usage : ./lier-registre.sh <projet> <serveur> <compte> <jeton>"
PROJET="${1:?$USAGE}"; SERVEUR="${2:?$USAGE}"; COMPTE="${3:?$USAGE}"; JETON="${4:?$USAGE}"

# Un Secret d'un type particulier : kubernetes.io/dockerconfigjson.
oc create secret docker-registry registre-externe -n "$PROJET" \
  --docker-server="$SERVEUR" \
  --docker-username="$COMPTE" \
  --docker-password="$JETON"
oc label secret registre-externe -n "$PROJET" app.kubernetes.io/part-of=telemarche

# Le Secret ne sert à rien tant qu'aucun compte de service ne le présente :
# « default » pour TIRER les images des pods…
oc secrets link default registre-externe --for=pull -n "$PROJET"
# … « builder » pour les builds, qui tirent l'image de base et poussent le résultat.
oc secrets link builder registre-externe -n "$PROJET"
