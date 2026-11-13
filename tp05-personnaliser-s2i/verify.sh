#!/usr/bin/env bash
# TP05 — niveau 2 : vos scripts .s2i/bin font construire la vitrine par l'image
# go-toolset d'origine. Niveau 3 : votre image de construction est bâtie dans
# le cluster, et son arrivée déclenche les builds de web et d'api.
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

step "Les fichiers ($(basename "$DIR"))"
no_holes "$DIR"
check "Les scripts .s2i/bin sont exécutables" test -x "$DIR/depot/.s2i/bin/assemble" -a -x "$DIR/depot/.s2i/bin/run"
check "Aucune fin de ligne Windows dans les scripts" bash -c "! grep -rlI \$'\r' '$DIR/depot/.s2i' '$DIR/telemach-go-builder'"
need_cluster
verify_project tp05-verify
depot_git
apply "$DIR"

step "Niveau 2 — des scripts dans le dépôt de l'application"
o apply -n "$NS" -f - >/dev/null <<FIN
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: web-niveau2
  labels: {app.kubernetes.io/part-of: telemarche}
---
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: web-niveau2
  labels: {app.kubernetes.io/part-of: telemarche}
spec:
  source: {type: Binary}
  strategy:
    type: Source
    sourceStrategy:
      from: {kind: DockerImage, name: "registry.access.redhat.com/ubi10/go-toolset:10.3"}
  output:
    to: {kind: ImageStreamTag, name: "web-niveau2:latest"}
FIN
copie_sources telemarche
cp -R "$DIR/depot/." "$TMP/"
build_dir web-niveau2 "$TMP"; NIVEAU2="$BUILD"
info "Build lancé : ${NIVEAU2:-aucun} (il se termine pendant la suite)"

step "Niveau 3 — l'image de construction"
build_dir telemach-go-builder "$DIR/telemach-go-builder"
build_reussi "telemach-go-builder se construit (stratégie Docker)" "$BUILD" 900
META='{.image.dockerImageMetadata.Config'
assert_eq "Le label désigne l'emplacement des scripts S2I" "image:///usr/libexec/s2i" \
  "$(jp imagestreamtag/telemach-go-builder:latest "$META.Labels.io\.openshift\.s2i\.scripts-url}")"
assert_contains "Le label io.openshift.tags la range parmi les images de construction" "builder" \
  "$(jp imagestreamtag/telemach-go-builder:latest "$META.Labels.io\.openshift\.tags}")"
assert_match "Elle ne tourne pas sous root (USER numérique)" '^[1-9][0-9]*$' "$(jp imagestreamtag/telemach-go-builder:latest "$META.User}")"

step "web et api, construits par cette image"
for c in web api; do
  assert_eq "$c : stratégie Source" "Source" "$(jp "buildconfig/$c" '{.spec.strategy.type}')"
  attendre_premier_build "$c" 120
  eval "BUILD_$c=\$BUILD"
done
# shellcheck disable=SC2154
build_reussi "L'arrivée de l'image de construction a déclenché le build de web" "$BUILD_web" 900
# shellcheck disable=SC2154
build_reussi "… et celui d'api" "$BUILD_api" 900
assert_contains "assemble a construit le programme désigné par COMPOSANT" "cmd/web" "$(o logs "build/$BUILD_web" -n "$NS" 2>/dev/null | grep -- '--->' || true)"
wait_rollout api 240
wait_rollout web 240
wait_route_http web /version 120 || true
assert_eq "La vitrine construite par S2I répond" "1.2" "$(route_get web /version | champ_json version || true)"
assert_contains "L'API construite par S2I répond derrière la vitrine" '"service":"api"' "$(route_get web /api/info || true)"
assert_eq "Les pods tournent sans privilège (restricted-v2)" "restricted-v2" \
  "$(o get pods -n "$NS" -l app=web -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}' 2>/dev/null || true)"

step "Niveau 2 — le résultat"
build_reussi "go-toolset construit la vitrine grâce à vos scripts .s2i/bin" "$NIVEAU2" 900
assert_contains "Votre assemble a remplacé celui de l'image" "Construction de cmd/web" "$(o logs "build/$NIVEAU2" -n "$NS" 2>/dev/null || true)"

summary
