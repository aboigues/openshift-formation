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
# TODO 8 : la sous-commande de « oc create secret » qui fabrique ce type.
oc create secret ______ registre-externe -n "$PROJET" \
  --docker-server="$SERVEUR" \
  --docker-username="$COMPTE" \
  --docker-password="$JETON"
oc label secret registre-externe -n "$PROJET" app.kubernetes.io/part-of=telemarche

# Le Secret ne sert à rien tant qu'aucun compte de service ne le présente :
# « default » pour TIRER les images des pods…                     TODO 9
oc secrets link ______ registre-externe --for=______ -n "$PROJET"
# … le compte de service des builds, qui tirent l'image de base et poussent le résultat.   TODO 10
oc secrets link ______ registre-externe -n "$PROJET"
