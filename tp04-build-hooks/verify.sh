#!/usr/bin/env bash
# TP04 — l'API est construite par OpenShift à partir du dépôt Git (stratégie
# Docker), le déploiement suit le build, et un hook post-commit empêche une
# version défectueuse d'atteindre le registre : l'ancienne continue de répondre.
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
need_cluster
verify_project tp04-verify
depot_git
apply "$DIR"

step "Le build depuis le dépôt Git"
assert_eq "Stratégie Docker" "Docker" "$(jp buildconfig/api '{.spec.strategy.type}')"
attendre_premier_build api 120
build_reussi "Le déclencheur ConfigChange a lancé un build, qui réussit" "$BUILD" 900
assert_match "Le build a retenu le commit construit" '^[0-9a-f]{40}$' "$(jp "build/$BUILD" '{.spec.revision.git.commit}')"
assert_contains "Le hook post-commit a contrôlé l'image avant sa publication" "self-test : OK" \
  "$(o logs "build/$BUILD" -n "$NS" 2>/dev/null | grep 'self-test' || true)"
EMPREINTE="$(jp imagestreamtag/api:latest '{.image.metadata.name}')"
assert_match "L'image est publiée sous api:latest" '^sha256:[0-9a-f]{64}$' "$EMPREINTE"

step "Le déploiement suit le build"
wait_rollout api 240
assert_contains "Le déclencheur a posé l'image construite dans le Deployment" "@$EMPREINTE" \
  "$(jp deployment/api '{.spec.template.spec.containers[0].image}')"
wait_route_http api /version 120 || true
assert_eq "L'API répond avec la version donnée au build (APP_VERSION)" "1.2" "$(route_get api /version | champ_json version || true)"

step "Une version défectueuse, envoyée depuis le poste"
copie_depot telemarche
cp "$HERE/pannes/catalogue.json" "$SRC/cmd/api/catalogue.json"
build_dir api "$TMP"
info "Build binaire lancé : ${BUILD:-aucun}"
attendre_build "$BUILD" 900
assert_eq "Le build de la version défectueuse échoue" "Failed" "$BUILD_PHASE"
assert_eq "C'est le hook post-commit qui l'arrête" "PostCommitHookFailed" "$(jp "build/$BUILD" '{.status.reason}')"
assert_contains "Le journal du build dit pourquoi" "prix invalide" "$(o logs "build/$BUILD" -n "$NS" 2>/dev/null | grep 'self-test' || true)"
assert_eq "L'image défectueuse n'a pas atteint le registre : api:latest n'a pas bougé" "$EMPREINTE" \
  "$(jp imagestreamtag/api:latest '{.image.metadata.name}')"
assert_eq "L'ancienne version continue de répondre" "1.2" "$(route_get api /version | champ_json version || true)"

summary
