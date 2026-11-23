#!/usr/bin/env bash
# TP06 — Télémarché entier (vitrine, API sur deux pods, base PostgreSQL
# persistante) décrit par un seul modèle. Le modèle est déposé dans le projet,
# instancié par oc new-app ; les deux pods de l'API voient les mêmes commandes,
# et ces commandes survivent au redémarrage de la base.
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"
MODELE="$DIR/telemarche.yaml"

step "Le modèle ($(basename "$DIR"))"
no_holes "$DIR"
command -v "$OC" >/dev/null 2>&1 || die "oc introuvable dans le PATH (voir docs/environnements.md)."
if ! RENDU="$(o process --local -f "$MODELE" -o yaml 2>&1)"; then
  ko "oc process refuse le modèle :"; printf '%s\n' "$RENDU" | tail -5 | sed 's/^/      /'; summary
fi
ok "oc process accepte le modèle"
assert_match "DB_PASSWORD est tiré au hasard (generate: expression)" '^DB_PASSWORD .* expression ' \
  "$(o process --local -f "$MODELE" --parameters 2>/dev/null | tr -s ' ')"

need_cluster
verify_project tp06-verify

step "Déposer le modèle, puis l'instancier"
apply "$MODELE"
if out="$(o new-app --template=telemarche -n "$NS" -p API_REPLICAS=2 2>&1)"; then
  ok "oc new-app --template=telemarche"
else
  ko "oc new-app --template=telemarche a échoué :"; printf '%s\n' "$out" | tail -8 | sed 's/^/      /'; summary
fi
MDP="$(jp secret/db-credentials '{.data.DB_PASSWORD}' | base64 -d 2>/dev/null || true)"
assert_match "Le mot de passe généré fait 16 caractères alphanumériques" '^[a-zA-Z0-9]{16}$' "$MDP"
assert_eq "Tous les objets portent le label du modèle (Secret compris)" "telemarche" \
  "$(jp secret/db-credentials '{.metadata.labels.template}')"
assert_eq "La base se redéploie en Recreate (un seul pod sur le volume)" "Recreate" "$(jp deployment/db '{.spec.strategy.type}')"
assert_eq "Le volume n'accepte qu'un pod à la fois (ReadWriteOncePod)" "ReadWriteOncePod" "$(jp pvc/db-data '{.spec.accessModes[0]}')"
assert_eq "La base monte le volume db-data" "db-data" \
  "$(jp deployment/db '{.spec.template.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}')"

step "Les pods"
wait_rollout db 360
wait_rollout api 300
wait_rollout web 180
assert_eq "L'API tourne sur 2 pods prêts" "2" "$(jp deployment/api '{.status.readyReplicas}')"
POD_API="$(o get pods -n "$NS" -l app=api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
assert_eq "Le conteneur d'initialisation migrate s'est terminé avec succès" "0" \
  "$(jp "pod/$POD_API" '{.status.initContainerStatuses[?(@.name=="migrate")].state.terminated.exitCode}')"
assert_contains "Son journal annonce la migration" "migration terminée" \
  "$(o logs -n "$NS" "$POD_API" -c migrate 2>/dev/null || true)"

step "Une commande, vue par tous les pods de l'API"
wait_route_http web /api/info 120 || true
assert_eq "L'API stocke dans PostgreSQL" "postgresql" "$(route_get web /api/info | champ_json stockage || true)"
URL="$(route_url web || true)"
COMMANDE="$(curl -sS -k -f -m 10 -X POST -H 'Content-Type: application/json' \
  -d '{"product_id":1,"quantity":3}' "$URL/api/orders" 2>/dev/null | champ_json id || true)"
assert_match "Commande passée par la vitrine" '^[0-9]+$' "$COMMANDE"
for pod in $(o get pods -n "$NS" -l app=api -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  assert_contains "Le pod $pod voit la commande n° $COMMANDE" "\"id\":$COMMANDE," \
    "$(o get --raw "/api/v1/namespaces/$NS/pods/http:$pod:8080/proxy/api/orders" --request-timeout=5s 2>/dev/null || true)"
done

step "La base redémarre, les commandes restent"
o delete pod -n "$NS" -l app=db --wait=true --timeout=120s >/dev/null 2>&1 || true
wait_rollout db 300
i=0; CMDS=""
until printf '%s' "$CMDS" | grep -qF "\"id\":$COMMANDE," || [ "$i" -ge 120 ]; do
  sleep 3; i=$((i+3)); CMDS="$(route_get web /api/orders || true)"
done
assert_contains "La commande n° $COMMANDE a survécu au nouveau pod de la base" "\"id\":$COMMANDE," "$CMDS"

summary
