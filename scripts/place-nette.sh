#!/usr/bin/env bash
# Supprime de votre projet courant les objets des TP (Télémarché, Télécaisse),
# et eux seuls : tout ce qui porte le label app.kubernetes.io/part-of des TP,
# plus les Secrets et ConfigMaps que les TP font créer à la main.
#   ./scripts/place-nette.sh [projet]
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"
need_cluster
PROJET="${1:-$(o project -q)}"
step "Place nette dans le projet $PROJET"
place_nette "$PROJET"
o secrets unlink default builder registre-externe -n "$PROJET" >/dev/null 2>&1 || true
info "Il reste : $(o get all -n "$PROJET" -o name 2>/dev/null | wc -l | tr -d ' ') objet(s) hors TP."
