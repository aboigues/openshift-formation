#!/usr/bin/env bash
# TP01 — web et api déployés à partir de leurs images, la vitrine publiée par
# une Route HTTPS, l'API configurée par une ConfigMap, une mise à jour suivie
# d'un retour arrière, et une DeploymentConfig convertie en Deployment.
source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$(target_dir "$HERE" "${1:-starter}")"
V10="docker.io/telemachlearning/telemarche-api:1.0"
V11="docker.io/telemachlearning/telemarche-api:1.1"

step "Les manifestes ($(basename "$DIR"))"
no_holes "$DIR"
need_cluster
verify_project tp01-verify
apply "$DIR"

step "Les déploiements"
wait_rollout api 240
wait_rollout web 240
assert_eq "2 réplicas d'API prêts" "2" "$(jp deployment/api '{.status.readyReplicas}')"
assert_eq "La configuration de l'API vient de la ConfigMap api-config" "api-config" \
  "$(jp deployment/api '{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}')"
assert_eq "L'API a une limite de mémoire" "64Mi" "$(jp deployment/api '{.spec.template.spec.containers[0].resources.limits.memory}')"
assert_eq "Le conteneur tourne sans privilège (SCC restricted-v2)" "restricted-v2" \
  "$(o get pods -n "$NS" -l app=api -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}')"

step "L'exposition"
assert_eq "La Route termine le TLS au routeur (edge)" "edge" "$(jp route/web '{.spec.tls.termination}')"
assert_eq "http:// est redirigé vers https://" "Redirect" "$(jp route/web '{.spec.tls.insecureEdgeTerminationPolicy}')"
wait_route_http web /version 120 || true
assert_contains "La vitrine répond en HTTPS par sa Route" '"service":"web"' "$(route_get web /version || true)"
assert_match "Une requête en HTTP reçoit une redirection" '^30[1278]$' \
  "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$(jp route/web '{.spec.host}')/" 2>/dev/null || true)"
assert_contains "La vitrine joint l'API par son Service (web -> api)" '"service":"api"' "$(route_get web /api/info || true)"
assert_eq "L'API n'est pas publiée : aucune Route ne la vise" "" \
  "$(o get routes -n "$NS" -o jsonpath='{range .items[?(@.spec.to.name=="api")]}{.metadata.name}{end}')"

step "Mise à jour, puis retour arrière"
o set image deployment/api -n "$NS" "api=$V11" >/dev/null
o rollout status deployment/api -n "$NS" --timeout=240s >/dev/null 2>&1 || true
assert_eq "Après oc set image, l'API répond en 1.1" "1.1" "$(route_get web /api/info | champ_json version || true)"
o rollout undo deployment/api -n "$NS" >/dev/null 2>&1 || true
o rollout status deployment/api -n "$NS" --timeout=240s >/dev/null 2>&1 || true
assert_eq "oc rollout undo ramène la 1.0" "$V10" "$(jp deployment/api '{.spec.template.spec.containers[0].image}')"
assert_eq "Après le retour arrière, l'API répond en 1.0" "1.0" "$(route_get web /api/info | champ_json version || true)"

step "La DeploymentConfig convertie"
wait_rollout stock 240
assert_eq "stock est un Deployment du groupe apps" "apps/v1" "$(jp deployment/stock '{.apiVersion}')"
assert_eq "Stratégie progressive (RollingUpdate)" "RollingUpdate" "$(jp deployment/stock '{.spec.strategy.type}')"
assert_contains "Le déclencheur d'image est devenu une annotation" '"name":"telemarche-api:1.0"' \
  "$(jp deployment/stock '{.metadata.annotations.image\.openshift\.io/triggers}')"
assert_contains "Le déclencheur a résolu l'image par son empreinte" "@sha256:" \
  "$(jp deployment/stock '{.spec.template.spec.containers[0].image}')"
assert_eq "Il ne reste aucune DeploymentConfig" "" "$(o get deploymentconfigs -n "$NS" -o name 2>/dev/null || true)"
wait_svc_http stock 8080 /version 60 || true

summary
