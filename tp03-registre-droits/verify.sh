#!/usr/bin/env bash
# TP03 — un ImageStream qui référence une image et la promeut par étiquette, le
# droit de tirer accordé à un second projet, et les identifiants d'un registre
# externe reliés aux comptes de service.
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

step "Les fichiers ($(basename "$DIR"))"
no_holes "$DIR"
need_cluster
verify_project tp03-verify
apply "$DIR/imagestream.yaml"

step "L'ImageStream"
i=0
until [ -n "$(jp imagestreamtag/api:prod '{.image.metadata.name}')" ] || [ "$i" -ge 90 ]; do sleep 3; i=$((i+3)); done
EMPREINTE="$(jp imagestreamtag/api:1.1 '{.image.metadata.name}')"
assert_match "L'étiquette 1.1 mémorise l'empreinte de l'image importée" '^sha256:[0-9a-f]{64}$' "$EMPREINTE"
if [ -z "$EMPREINTE" ]; then
  warn "Import en échec ? $(jp imagestream/api '{.status.tags[*].conditions[*].message}')"
fi
assert_eq "prod pointe vers une étiquette, pas vers un registre" "ImageStreamTag" "$(jp imagestream/api '{.spec.tags[?(@.name=="prod")].from.kind}')"
assert_eq "Promotion : prod désigne la même image que 1.1" "$EMPREINTE" "$(jp imagestreamtag/api:prod '{.image.metadata.name}')"
assert_eq "L'image d'origine est revérifiée périodiquement" "true" "$(jp imagestream/api '{.spec.tags[?(@.name=="1.1")].importPolicy.scheduled}')"
assert_eq "Résolution locale des noms d'images activée" "true" "$(jp imagestream/api '{.spec.lookupPolicy.local}')"
o create deployment essai -n "$NS" --image=api:prod >/dev/null 2>&1 || true
o label deployment essai -n "$NS" app.kubernetes.io/part-of=telemarche >/dev/null 2>&1 || true
if o rollout status deployment/essai -n "$NS" --timeout=180s >/dev/null 2>&1; then
  ok "Un Deployment qui écrit « image: api:prod » démarre"
else
  ko "Un Deployment qui écrit « image: api:prod » ne démarre pas"; debug_pods
fi
assert_contains "Le nom court a été remplacé par l'empreinte" "@$EMPREINTE" "$(o get pods -n "$NS" -l app=essai -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || true)"

step "Le partage entre projets"
if second_project tp03-verify-prod; then
  info "Second projet : $NS2"
  "$HERE/outils/consommateur.sh" "$NS" "$NS2" >/dev/null
  i=0; RAISON=""
  while [ "$i" -lt 90 ]; do
    RAISON="$(o get pods -n "$NS2" -l app=api -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)"
    case "$RAISON" in ErrImagePull|ImagePullBackOff) break ;; esac
    sleep 3; i=$((i+3))
  done
  assert_match "Sans droit, le second projet ne peut pas tirer l'image" '^(ErrImagePull|ImagePullBackOff)$' "$RAISON"
  if "$DIR/partager.sh" "$NS" "$NS2" >/dev/null 2>&1; then ok "partager.sh s'exécute"; else ko "partager.sh a échoué"; fi
  assert_contains "Le droit est donné dans le projet des images, au compte default du second projet" \
    "system:serviceaccount:$NS2:default" "$(o policy who-can get imagestreams/layers -n "$NS" 2>/dev/null || true)"
  o delete pods -n "$NS2" -l app=api --wait=false >/dev/null 2>&1 || true   # sans attendre le prochain essai du kubelet
  wait_rollout api 240 "$NS2"
  assert_contains "Le pod du second projet tourne avec l'image promue" "$NS/api" \
    "$(o get pods -n "$NS2" -l app=api -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || true)"
else
  skip "Le pod d'un second projet démarre avec votre image" "pas de second projet ici ; à faire en binôme, voir l'étape 4"
  if "$DIR/partager.sh" "$NS" "$NS" >/dev/null 2>&1; then ok "partager.sh s'exécute"; else ko "partager.sh a échoué"; fi
  assert_contains "partager.sh accorde le droit au compte de service default" \
    "system:serviceaccount:$NS:default" "$(o policy who-can get imagestreams/layers -n "$NS" 2>/dev/null || true)"
fi

step "Le registre externe privé"
o secrets unlink default builder registre-externe -n "$NS" >/dev/null 2>&1 || true
if "$DIR/lier-registre.sh" "$NS" registre.exemple.com robot-lecture "$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')" >/dev/null 2>&1; then
  ok "lier-registre.sh s'exécute"
else
  ko "lier-registre.sh a échoué"
fi
assert_eq "Le Secret est du type attendu par les registres" "kubernetes.io/dockerconfigjson" "$(jp secret/registre-externe '{.type}')"
assert_contains "Le compte default le présente pour tirer les images" "registre-externe" "$(jp serviceaccount/default '{.imagePullSecrets[*].name}')"
assert_contains "Le compte builder le présente pour les builds" "registre-externe" "$(jp serviceaccount/builder '{.secrets[*].name}')"
if [ "$MODE" != "jetable" ]; then   # ne pas laisser de faux identifiants dans un projet durable
  o secrets unlink default builder registre-externe -n "$NS" >/dev/null 2>&1 || true
  o delete secret registre-externe -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
fi

summary
