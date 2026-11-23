#!/usr/bin/env bash
# TP07 — une API lente à démarrer, mais jamais redémarrée à tort (sonde de
# démarrage) ; une mise à jour sous trafic continu, sans une seule erreur
# (maxUnavailable 0, readiness, vidange) ; un budget de perturbation ; puis la
# version 1.1 en canari, une requête sur dix.
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
need_cluster
verify_project tp07-verify
apply "$DIR/api.yaml"

step "Les sondes"
C='{.spec.template.spec.containers[?(@.name=="api")]'
assert_eq "Sonde de démarrage sur /healthz" "/healthz" "$(jp deployment/api "$C.startupProbe.httpGet.path}")"
PERIODE="$(jp deployment/api "$C.startupProbe.periodSeconds}")"; ESSAIS="$(jp deployment/api "$C.startupProbe.failureThreshold}")"
if [ "$(( ${PERIODE:-10} * ${ESSAIS:-3} ))" -ge 30 ]; then
  ok "La sonde de démarrage laisse au moins 30 s ($ESSAIS × $PERIODE s) pour 20 s de démarrage"
else
  ko "La sonde de démarrage ne laisse que $(( ${PERIODE:-10} * ${ESSAIS:-3} )) s pour 20 s de démarrage"
fi
assert_eq "Sonde de disponibilité sur /ready" "/ready" "$(jp deployment/api "$C.readinessProbe.httpGet.path}")"
assert_eq "Sonde de vie sur /healthz, qui ne dépend pas de la base" "/healthz" "$(jp deployment/api "$C.livenessProbe.httpGet.path}")"
assert_eq "Mise à jour sans perte de capacité (maxUnavailable 0)" "0" "$(jp deployment/api '{.spec.strategy.rollingUpdate.maxUnavailable}')"
GRACE="$(jp deployment/api '{.spec.template.spec.terminationGracePeriodSeconds}')"
if [ "${GRACE:-0}" -gt 10 ]; then ok "Délai d'arrêt ($GRACE s) supérieur à la vidange (10 s)"
else ko "Délai d'arrêt (${GRACE:-?} s) trop court pour une vidange de 10 s"; fi

step "Un démarrage lent, sans redémarrage"
wait_rollout api 240
assert_eq "Aucun redémarrage de conteneur" "0 0" "$(o get pods -n "$NS" -l app=api -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}' 2>/dev/null || true)"
assert_eq "Le budget de perturbation autorise l'arrêt d'un pod, pas plus" "1" "$(jp poddisruptionbudget/api '{.status.disruptionsAllowed}')"

step "Une mise à jour sous trafic continu"
tmpdir; JOURNAL="$TMP/codes"
(
  while [ ! -f "$TMP/fin" ]; do
    if svc_get api 8080 /version >/dev/null; then echo 200; else echo KO; fi
    sleep 0.2
  done > "$JOURNAL"
) &
TRAFIC=$!
sleep 3
o set env deployment/api -n "$NS" VERSION_DEPLOIEMENT="$(date +%s)" >/dev/null
info "Nouveau déploiement lancé ; le trafic continue."
wait_rollout api 300
sleep 3; touch "$TMP/fin"; wait "$TRAFIC" 2>/dev/null || true
TOTAL="$(wc -l < "$JOURNAL" | tr -d ' ')"; ERREURS="$(grep -c KO "$JOURNAL" || true)"
if [ "$TOTAL" -ge 30 ]; then ok "$TOTAL requêtes pendant la mise à jour"; else ko "Trop peu de requêtes pendant la mise à jour ($TOTAL)"; fi
assert_eq "Aucune requête en échec pendant la mise à jour" "0" "$ERREURS"

step "La version 1.1 en canari"
apply "$DIR/canari.yaml"
wait_rollout api-canari 240
assert_eq "La Route envoie 90 % du trafic au Service api" "90" "$(jp route/api '{.spec.to.weight}')"
assert_eq "… et 10 % au Service api-canari" "api-canari=10" \
  "$(jp route/api '{range .spec.alternateBackends[*]}{.name}={.weight}{end}')"
wait_route_http api /version 120 || true
N10=0; N11=0
for _ in $(seq 1 100); do
  case "$(route_get api /version | champ_json version || true)" in
    1.0) N10=$((N10+1)) ;; 1.1) N11=$((N11+1)) ;;
  esac
done
info "Sur 100 requêtes : $N10 en 1.0, $N11 en 1.1"
if [ "$N11" -ge 3 ] && [ "$N11" -le 25 ] && [ "$N10" -ge 70 ]; then
  ok "Le canari reçoit environ une requête sur dix"
else
  ko "Répartition inattendue : $N10 en 1.0, $N11 en 1.1 (attendu : environ 90 / 10)"
fi

summary
