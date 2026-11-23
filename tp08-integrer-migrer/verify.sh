#!/usr/bin/env bash
# TP08 — Télécaisse, une application WildFly installée à la main, migre sur
# OpenShift : construite par l'image wildfly-s2i, configurée par
# l'environnement, reliée à sa base restée « dans le SI » par un Service
# ExternalName, et à l'API de Télémarché par le nom de son Service.
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
need_cluster
verify_project tp08-verify

step "Le décor : la base du SI, l'API de Télémarché"
if second_project tp08-si; then PROJET_SI="$NS2"; else PROJET_SI="$NS"; fi
if ! SORTIE="$("$HERE/outils/base-si.sh" "$PROJET_SI" 2>&1)"; then
  ko "outils/base-si.sh a échoué :"; printf '%s\n' "$SORTIE" | tail -5 | sed 's/^/      /'; summary
fi
ok "La base de la caisse tourne dans le projet $PROJET_SI, historique chargé"
HOTE_SI="si-caisse.${PROJET_SI}.svc.cluster.local"
secret_si() { o get secret si-caisse -n "$PROJET_SI" -o "jsonpath={.data.$1}" | base64 -d; }
o create secret generic telecaisse-db -n "$NS" \
  --from-literal=POSTGRESQL_USER="$(secret_si POSTGRESQL_USER)" \
  --from-literal=POSTGRESQL_PASSWORD="$(secret_si POSTGRESQL_PASSWORD)" \
  --from-literal=POSTGRESQL_DATABASE="$(secret_si POSTGRESQL_DATABASE)" >/dev/null
apply "$HERE/outils/telemarche.yaml"
depot_git
apply "$DIR"

step "La base, par un nom"
assert_eq "caisse-db est un Service ExternalName" "ExternalName" "$(jp service/caisse-db '{.spec.type}')"
o patch service caisse-db -n "$NS" --type=merge -p "{\"spec\":{\"externalName\":\"$HOTE_SI\"}}" >/dev/null
info "caisse-db pointe, pour la vérification, sur $HOTE_SI"
C='{.spec.template.spec.containers[?(@.name=="telecaisse")]'
assert_eq "Télécaisse cherche sa base sous le nom caisse-db" "caisse-db" \
  "$(jp deployment/telecaisse "$C.env[?(@.name==\"POSTGRESQL_HOST\")].value}")"
assert_eq "Ses identifiants viennent du Secret telecaisse-db" "telecaisse-db" "$(jp deployment/telecaisse "$C.envFrom[0].secretRef.name}")"
assert_eq "La sonde de disponibilité interroge la base" "/api/sante/prete" "$(jp deployment/telecaisse "$C.readinessProbe.httpGet.path}")"

step "Le build WildFly"
assert_eq "Stratégie Source" "Source" "$(jp buildconfig/telecaisse '{.spec.strategy.type}')"
attendre_premier_build telecaisse 120
build_reussi "Maven compile, Galleon assemble le serveur" "$BUILD" 1500

step "Télécaisse en service"
wait_rollout api 180
wait_rollout telecaisse 600
wait_route_http telecaisse /api/info 120 || true
assert_eq "Télécaisse 2.0 répond par sa Route" "2.0" "$(route_get telecaisse /api/info | champ_json version || true)"
assert_contains "L'historique de l'ancienne caisse est lu dans la base du SI" "caisse-magasin-1" \
  "$(route_get telecaisse /api/tickets || true)"
PRIX="$(svc_get api 8080 /api/products/2 | champ_json prix_centimes || true)"
URL="$(route_url telecaisse || true)"
VENTE="$(curl -sS -k -m 15 -X POST -H 'Content-Type: application/json' -d '{"produit":2,"quantite":3}' "$URL/api/ventes" 2>/dev/null || true)"
assert_match "Une vente est enregistrée" '"id":[0-9]+' "$VENTE"
assert_eq "Son montant vient du prix de Télémarché (3 × ${PRIX:-?} centimes)" "$(( ${PRIX:-0} * 3 ))" \
  "$(printf '%s' "$VENTE" | champ_json montantCentimes)"
TICKET="$(printf '%s' "$VENTE" | champ_json id)"
assert_eq "Le ticket n° ${TICKET:-?} est bien dans la base du SI" "1" \
  "$(o exec -n "$PROJET_SI" deployment/si-caisse -- psql -tA -U caisse -d caisse \
      -c "SELECT count(*) FROM tickets WHERE id = ${TICKET:-0}" 2>/dev/null || true)"

summary
