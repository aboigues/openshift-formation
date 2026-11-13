#!/usr/bin/env bash
# Construit DANS LE CLUSTER l'image décrite par <dossier>/Dockerfile, puis la
# déploie dans votre projet courant.
#
#   ./outils/deployer.sh heritage      # l'image historique  -> api-heritage
#   ./outils/deployer.sh starter       # votre Dockerfile    -> api-starter
#
# Ce script enchaîne trois commandes que vous étudierez au jour 2 (module 4) :
# oc new-build, oc start-build --from-dir, oc new-app. Aujourd'hui, c'est une
# boîte noire : ce qui nous intéresse est ce qui arrive à l'image une fois lancée.
set -euo pipefail
ICI="$(cd "$(dirname "$0")/.." && pwd)"
RACINE="$(cd "$ICI/.." && pwd)"
VARIANTE="${1:?Usage : ./outils/deployer.sh <heritage|starter|solution>}"
NOM="api-$VARIANTE"
[ -f "$ICI/$VARIANTE/Dockerfile" ] || { echo "Pas de Dockerfile dans $ICI/$VARIANTE" >&2; exit 1; }

# Le contexte de construction : les sources de l'application, plus le Dockerfile.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -R "$RACINE/apps/telemarche/." "$tmp/"
cp -R "$ICI/$VARIANTE/." "$tmp/"

ETIQUETTES="app=$NOM,app.kubernetes.io/part-of=telemarche"
oc get buildconfig "$NOM" >/dev/null 2>&1 \
  || oc new-build --name="$NOM" --binary --strategy=docker --labels="$ETIQUETTES" >/dev/null
echo "▶ Construction de l'image $NOM dans le cluster (quelques minutes la première fois)…"
oc start-build "$NOM" --from-dir="$tmp" --follow --wait

if oc get deployment "$NOM" >/dev/null 2>&1; then
  oc rollout restart "deployment/$NOM" >/dev/null
else
  oc new-app --image-stream="$NOM:latest" --name="$NOM" --labels="$ETIQUETTES" >/dev/null
fi
echo "▶ Déployé. À vous d'observer :"
echo "    oc get pods -l app=$NOM -w        (Ctrl+C pour sortir)"
echo "    oc logs deployment/$NOM"
