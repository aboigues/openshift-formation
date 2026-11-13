#!/usr/bin/env bash
# Helpers partagés par tous les verify.sh des TP.
# Usage : source "$(cd "$(dirname "$0")/.." && pwd)/scripts/lib.sh"
#
# Où la vérification travaille-t-elle ? Tout dépend de vos droits sur le cluster :
#
#   - vous pouvez créer des projets (OpenShift Local, cluster personnel) :
#     chaque verify.sh crée SON projet jetable (tpNN-verify-<vous>), supprimé à
#     la fin. Il ne touche jamais à votre projet de travail. KEEP=1 le conserve.
#   - vous ne le pouvez pas (Developer Sandbox, cluster d'entreprise) : la
#     vérification se fait DANS votre projet courant. Les objets des TP y sont
#     supprimés, puis recréés à partir de starter/ ou de solution/, et laissés
#     en place à la fin. Une confirmation est demandée (OUI=1 pour la donner
#     d'avance).
#   - PROJET_VERIF=<projet> désigne un projet existant à utiliser à la place.
#
# Autres réglages : voir docs/environnements.md.

set -euo pipefail

OC="${OC:-oc}"
RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# L'adresse écrite dans les manifestes et les README. verify.sh la remplace par
# le dépôt réellement utilisé pour les builds (voir depot_git).
DEPOT_OFFICIEL="https://github.com/aboigues/openshift-formation"
IMAGE_DEPOT="registry.access.redhat.com/ubi10/httpd-24:10.3"

# Le label que portent TOUS les objets des TP : c'est lui qui permet de faire
# place nette sans toucher au reste d'un projet.
SELECTEUR_TP='app.kubernetes.io/part-of in (telemarche,telecaisse)'
# Les objets créés à la main dans les TP, que rien n'oblige à porter un label.
SECRETS_TP="db-credentials telecaisse-db registre-externe webhook-api"
CONFIGMAPS_TP="api-config ca-entreprise"

# Couleurs (désactivées si pas de TTY, ex. CI)
if [ -t 1 ]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BLUE=''; NC=''
fi

PASS=0
FAIL=0
SKIP=0
NS=""; NS2=""; MODE=""; MODE2=""
DEPOT=""; REF="main"
TMPDIRS=()

step()  { printf "${BLUE}▶ %s${NC}\n" "$*"; }
info()  { printf "  %s\n" "$*"; }
warn()  { printf "  ${YELLOW}⚠ %s${NC}\n" "$*"; }
die()   { printf "${RED}✗ %s${NC}\n" "$*" >&2; exit 1; }
ok()    { printf "  ${GREEN}✓${NC} %s\n" "$*"; PASS=$((PASS+1)); }
ko()    { printf "  ${RED}✗${NC} %s\n" "$*"; FAIL=$((FAIL+1)); }

# skip "description" "raison" : une vérification impossible dans CET
# environnement (pas de second projet, pas de podman…). Ni réussie, ni en échec.
skip()  { printf "  ${YELLOW}○${NC} %s ${YELLOW}(non vérifié : %s)${NC}\n" "$1" "$2"; SKIP=$((SKIP+1)); }

o() { "$OC" "$@"; }

# check "description" commande...  → exécute, valide le code retour
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else ko "$desc"; fi
}

# assert_eq "description" "attendu" "obtenu"
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    ok "$desc"
  else
    printf "  ${RED}✗${NC} %s ${YELLOW}(attendu : « %s », obtenu : « %s »)${NC}\n" "$desc" "$expected" "$actual"; FAIL=$((FAIL+1))
  fi
}

# assert_contains "description" "aiguille" "botte de foin"
assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    ok "$desc"
  else
    printf "  ${RED}✗${NC} %s ${YELLOW}(attendu : « %s »)${NC}\n" "$desc" "$needle"; FAIL=$((FAIL+1))
  fi
}

# assert_match "description" "expression régulière étendue" "texte"
assert_match() {
  local desc="$1" re="$2" text="$3"
  if printf '%s' "$text" | grep -qE -- "$re"; then
    ok "$desc"
  else
    printf "  ${RED}✗${NC} %s ${YELLOW}(obtenu : « %s »)${NC}\n" "$desc" "$text"; FAIL=$((FAIL+1))
  fi
}

# tmpdir : un dossier temporaire, supprimé à la sortie. Le chemin est rendu dans
# la variable TMP (et non sur la sortie standard : un sous-shell perdrait la
# liste des dossiers à supprimer).
tmpdir() { TMP="$(mktemp -d)"; TMPDIRS+=("$TMP"); }

# ---------------------------------------------------------------------------
# Cluster et projet de vérification
# ---------------------------------------------------------------------------

# need_cluster : échoue tôt et clairement si oc n'est pas connecté à OpenShift.
need_cluster() {
  command -v "$OC" >/dev/null 2>&1 || die "oc introuvable dans le PATH (voir docs/environnements.md)."
  if ! o whoami --request-timeout=10s >/dev/null 2>&1; then
    die "Non connecté à un cluster, ou jeton expiré : refaites « oc login » (console web, menu du compte, Copy login command)."
  fi
  if ! o api-resources --api-group=route.openshift.io -o name 2>/dev/null | grep -q '^routes'; then
    die "Ce cluster n'est pas un OpenShift (pas d'objet Route) : $(o whoami --show-server)."
  fi
}

# suffixe : votre identifiant, réduit à ce qu'un nom de projet accepte. Deux
# participants d'un même cluster ne se marchent ainsi pas dessus.
suffixe() {
  o whoami | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-' | sed 's/^-*//; s/-*$//; s/--*/-/g' | cut -c1-24
}

peut_creer_projet() {
  [ "${PROJET_JETABLE:-1}" = "1" ] || return 1
  o auth can-i create projectrequests.project.openshift.io >/dev/null 2>&1
}

confirmer() {
  local projet="$1" rep
  [ "${OUI:-0}" = "1" ] && return 0
  printf "  ${YELLOW}⚠ La vérification se fait DANS le projet « %s ».${NC}\n" "$projet"
  printf "    Les objets des TP (Télémarché, Télécaisse) y seront supprimés, puis recréés.\n"
  if [ -t 0 ]; then
    read -r -p "    Continuer ? [o/N] " rep
    case "$rep" in o|O|oui|Oui|y|Y) return 0 ;; esac
    die "Abandon : rien n'a été modifié."
  fi
  die "Confirmation impossible sans terminal : relancez avec OUI=1 ./verify.sh …"
}

# place_nette PROJET : supprime les objets des TP, et eux seuls.
place_nette() {
  local ns="$1"
  # shellcheck disable=SC2086
  {
    o delete all,configmap,secret,pvc,rolebinding,template,poddisruptionbudget,endpointslices.discovery.k8s.io \
      -n "$ns" -l "$SELECTEUR_TP" --ignore-not-found --timeout=180s >/dev/null 2>&1 || true
    o delete secret $SECRETS_TP -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
    o delete configmap $CONFIGMAPS_TP -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
  }
  # Les pods en cours d'arrêt occupent encore le quota : on les laisse partir.
  local i=0
  while [ -n "$(o get pods -n "$ns" -l "$SELECTEUR_TP" -o name 2>/dev/null)" ] && [ "$i" -lt 90 ]; do
    sleep 3; i=$((i+3))
  done
}

# creer_projet NOM : (re)crée un projet jetable et attend qu'il soit utilisable.
creer_projet() {
  local ns="$1" i=0
  if o get project "$ns" >/dev/null 2>&1; then
    o delete project "$ns" --wait=true --timeout=180s >/dev/null 2>&1 || true
    while o get project "$ns" >/dev/null 2>&1; do
      sleep 3; i=$((i+3)); [ "$i" -lt 240 ] || die "Le projet $ns ne finit pas de se supprimer."
    done
  fi
  # --skip-config-write : votre projet courant ne change pas.
  o new-project "$ns" --skip-config-write >/dev/null || die "Création du projet $ns impossible."
  # Les comptes de service arrivent une ou deux secondes après le projet : un
  # build lancé avant l'arrivée de « builder » échoue.
  i=0
  until o get serviceaccount builder default -n "$ns" >/dev/null 2>&1; do
    sleep 2; i=$((i+2)); [ "$i" -lt 60 ] || die "Les comptes de service du projet $ns n'arrivent pas."
  done
}

nettoyage() {
  local d
  for d in "${TMPDIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done
  if [ "${KEEP:-0}" = "1" ]; then
    [ "$MODE" = "jetable" ] && info "KEEP=1 : projet $NS conservé (oc delete project $NS pour le supprimer)."
    return 0
  fi
  [ "$MODE" = "jetable" ] && o delete project "$NS" --wait=false >/dev/null 2>&1
  [ "$MODE2" = "jetable" ] && o delete project "$NS2" --wait=false >/dev/null 2>&1
  return 0
}

# verify_project NOM : choisit le projet de vérification (voir l'en-tête).
verify_project() {
  local base="$1"
  trap nettoyage EXIT
  if [ -n "${PROJET_VERIF:-}" ]; then
    NS="$PROJET_VERIF"; MODE="dedie"
    o get project "$NS" >/dev/null 2>&1 || die "PROJET_VERIF=$NS : projet introuvable ou inaccessible."
  elif peut_creer_projet; then
    NS="$base-$(suffixe)"; MODE="jetable"
    creer_projet "$NS"
  else
    NS="$(o project -q 2>/dev/null)" || die "Aucun projet courant : « oc project <votre projet> »."
    MODE="courant"
  fi
  if [ "$MODE" != "jetable" ]; then
    confirmer "$NS"
    place_nette "$NS"
  fi
  info "Projet de vérification : $NS ($MODE)"
}

# second_project NOM : un second projet, pour les TP qui en demandent deux.
# Renvoie 1 s'il n'y en a pas : à l'appelant de passer la vérification (skip).
second_project() {
  local base="$1"
  if [ -n "${PROJET_2:-}" ]; then
    NS2="$PROJET_2"; MODE2="dedie"
    o get project "$NS2" >/dev/null 2>&1 || die "PROJET_2=$NS2 : projet introuvable ou inaccessible."
    place_nette "$NS2"
    return 0
  fi
  if [ "$MODE" = "jetable" ]; then
    NS2="$base-$(suffixe)"; MODE2="jetable"
    creer_projet "$NS2"
    return 0
  fi
  return 1
}

# target_dir : résout starter|solution en chemin absolu (à côté du verify.sh).
target_dir() {
  local here="$1" target="$2"
  case "$target" in
    starter|solution) ;;
    *) die "Usage : ./verify.sh [starter|solution]" ;;
  esac
  [ -d "$here/$target" ] || die "Dossier introuvable : $here/$target"
  printf '%s/%s' "$here" "$target"
}

# no_holes DOSSIER : refuse d'aller plus loin s'il reste des trous « ______ ».
no_holes() {
  local dir="$1" holes
  holes="$(grep -rn '______' "$dir" 2>/dev/null || true)"
  if [ -n "$holes" ]; then
    printf "  ${RED}✗${NC} Il reste des trous à compléter :\n"
    printf '%s\n' "$holes" | sed "s|$dir/||; s/^/      /"
    FAIL=$((FAIL+1))
    summary
  fi
  ok "Aucun trou « ______ » restant"
}

# rendre FICHIER : le manifeste tel qu'il sera appliqué. L'adresse officielle du
# dépôt y est remplacée par celle du dépôt de vérification (voir depot_git).
rendre() {
  if [ -n "$DEPOT" ] && [ "$DEPOT" != "$DEPOT_OFFICIEL" ]; then
    sed -e "s#${DEPOT_OFFICIEL}\(\.git\)\{0,1\}#${DEPOT}#g" -e "s#^\( *ref: *\)main *\$#\1${REF}#" "$1"
  else
    cat "$1"
  fi
}

# apply FICHIER|DOSSIER [PROJET] : applique dans le projet de vérification. Pour
# un dossier : ses fichiers .yaml, dans l'ordre alphabétique, sans descendre
# dans les sous-dossiers.
apply() {
  local cible="$1" ns="${2:-$NS}" out f fichiers=()
  if [ -d "$cible" ]; then
    for f in "$cible"/*.yaml "$cible"/*.yml; do [ -f "$f" ] && fichiers+=("$f"); done
  else
    fichiers=("$cible")
  fi
  [ "${#fichiers[@]}" -gt 0 ] || { ko "Aucun manifeste dans $cible"; summary; }
  for f in "${fichiers[@]}"; do
    if ! out="$(rendre "$f" | o apply -n "$ns" -f - 2>&1)"; then
      printf "  ${RED}✗${NC} oc apply a échoué (%s) :\n" "$(basename "$f")"
      printf '%s\n' "$out" | sed 's/^/      /'
      FAIL=$((FAIL+1))
      summary
    fi
    printf '%s\n' "$out" | sed 's/^/  /'
  done
}

# ---------------------------------------------------------------------------
# Le dépôt Git des builds
# ---------------------------------------------------------------------------

# depot_git : fixe DEPOT et REF, l'adresse que les BuildConfigs vont cloner.
#
#   - par défaut : VOTRE copie de travail, telle qu'elle est sur le disque
#     (modifications non commitées comprises), servie par un petit serveur
#     HTTP dans le projet de vérification. Les builds ne dépendent ainsi ni de
#     GitHub, ni de ce qui y est publié : on teste ce que l'on a sous les yeux.
#   - DEPOT_GIT=<adresse> [REF_GIT=<branche>] : un dépôt existant, par exemple
#     DEPOT_GIT=https://github.com/aboigues/openshift-formation.
depot_git() {
  REF="${REF_GIT:-main}"
  if [ -n "${DEPOT_GIT:-}" ]; then
    DEPOT="$DEPOT_GIT"
    info "Sources des builds : $DEPOT ($REF)"
    return 0
  fi
  command -v git >/dev/null 2>&1 || die "git introuvable (ou donnez un dépôt : DEPOT_GIT=$DEPOT_OFFICIEL)."
  REF="main"
  tmpdir; local tmp="$TMP"
  mkdir "$tmp/src"
  if git -C "$RACINE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ( cd "$RACINE" && git ls-files -co --exclude-standard -z \
        | tar --null --ignore-failed-read -T - -cf - 2>/dev/null ) | tar -xf - -C "$tmp/src"
  else
    tar -C "$RACINE" --exclude=.git -cf - . | tar -xf - -C "$tmp/src"
  fi
  (
    cd "$tmp/src"
    git init -q -b main
    git add -A
    # Sous Windows, Git ne lit pas le droit d'exécution sur le disque : on le
    # pose dans l'index pour les scripts (S2I refuse un script non exécutable).
    git ls-files -z | grep -zE '(\.sh$|/\.?s2i/bin/[^/]+$)' | xargs -0 -r git update-index --chmod=+x
    git -c user.name=verify -c user.email=verify@localhost commit -q -m "Copie de travail"
    git clone -q --bare . "$tmp/openshift-formation.git"
    git -C "$tmp/openshift-formation.git" update-server-info
  ) || die "Préparation du dépôt de vérification impossible."

  o apply -n "$NS" -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: depot-git
  labels: {app: depot-git, app.kubernetes.io/part-of: telemarche}
spec:
  replicas: 1
  selector:
    matchLabels: {app: depot-git}
  template:
    metadata:
      labels: {app: depot-git, app.kubernetes.io/part-of: telemarche}
    spec:
      containers:
        - name: httpd
          image: ${IMAGE_DEPOT}
          ports:
            - containerPort: 8080
          readinessProbe:
            tcpSocket: {port: 8080}
            periodSeconds: 2
          resources:
            requests: {cpu: 20m, memory: 64Mi}
            limits: {memory: 128Mi}
          volumeMounts:
            - name: depots
              mountPath: /var/www/html
      volumes:
        - name: depots
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: depot-git
  labels: {app: depot-git, app.kubernetes.io/part-of: telemarche}
spec:
  selector: {app: depot-git}
  ports:
    - port: 8080
      targetPort: 8080
EOF
  if ! o rollout status deployment/depot-git -n "$NS" --timeout=240s >/dev/null 2>&1; then
    ko "Le dépôt de vérification (depot-git) ne démarre pas"; debug_pods; summary
  fi
  tar -C "$tmp" -cf - openshift-formation.git \
    | o exec -i -n "$NS" deployment/depot-git -- tar -xf - -C /var/www/html \
    || die "Copie des sources vers le dépôt de vérification impossible."
  DEPOT="http://depot-git.${NS}.svc.cluster.local:8080/openshift-formation.git"
  info "Sources des builds : votre copie de travail, servie par depot-git"
}

# copie_sources APPLICATION : copie apps/<application> dans un dossier
# temporaire (rendu dans TMP), pour y poser des fichiers avant un build binaire.
copie_sources() {
  tmpdir
  cp -R "$RACINE/apps/$1/." "$TMP/"
}

# copie_depot APPLICATION : la même chose, mais rangée comme dans le dépôt
# (TMP/apps/<application>), pour un build binaire sur un BuildConfig qui porte
# un contextDir : le dossier envoyé tient alors lieu de dépôt entier. Le dossier
# de l'application est rendu dans SRC.
copie_depot() {
  tmpdir
  mkdir -p "$TMP/apps/$1"
  cp -R "$RACINE/apps/$1/." "$TMP/apps/$1/"
  # shellcheck disable=SC2034
  SRC="$TMP/apps/$1"
}

# ---------------------------------------------------------------------------
# Builds
# ---------------------------------------------------------------------------

# attendre_build BUILD [TIMEOUT_S] : attend la fin du build, phase dans BUILD_PHASE.
attendre_build() {
  local b="$1" timeout="${2:-900}" i=0
  BUILD_PHASE=""
  while :; do
    BUILD_PHASE="$(jp "build/$b" '{.status.phase}')"
    case "$BUILD_PHASE" in Complete|Failed|Error|Cancelled) return 0 ;; esac
    i=$((i+5))
    if [ "$i" -ge "$timeout" ]; then BUILD_PHASE="${BUILD_PHASE:-absent} (pas terminé après ${timeout}s)"; return 0; fi
    sleep 5
  done
}

# dernier_build BUILDCONFIG : le nom du dernier build lancé (vide s'il n'y en a pas).
dernier_build() {
  local n; n="$(jp "buildconfig/$1" '{.status.lastVersion}')"
  if [ -n "$n" ] && [ "$n" != "0" ]; then printf '%s-%s' "$1" "$n"; fi
  return 0
}

# attendre_premier_build BUILDCONFIG [TIMEOUT_S] : attend qu'un déclencheur
# (ConfigChange, ImageChange) ait lancé un build ; son nom est rendu dans BUILD.
attendre_premier_build() {
  local bc="$1" timeout="${2:-120}" i=0
  BUILD=""
  while [ -z "$BUILD" ] && [ "$i" -lt "$timeout" ]; do
    BUILD="$(dernier_build "$bc")"
    [ -n "$BUILD" ] || { sleep 3; i=$((i+3)); }
  done
  return 0
}

# build_dir BUILDCONFIG DOSSIER : lance un build binaire ; nom rendu dans BUILD.
build_dir() {
  local out
  BUILD=""
  if out="$(o start-build "$1" -n "$NS" --from-dir="$2" -o name 2>&1)"; then
    BUILD="$(printf '%s\n' "$out" | sed -n 's#^build[^/]*/##p' | tail -1)"
  else
    printf '%s\n' "$out" | tail -5 | sed 's/^/      /'
  fi
  return 0
}

# build_reussi "description" BUILD [TIMEOUT_S] : le build doit finir « Complete ».
build_reussi() {
  local desc="$1" b="$2" timeout="${3:-900}"
  if [ -z "$b" ]; then ko "$desc (aucun build lancé)"; return 0; fi
  attendre_build "$b" "$timeout"
  if [ "$BUILD_PHASE" = "Complete" ]; then
    ok "$desc ($b)"
  else
    printf "  ${RED}✗${NC} %s ${YELLOW}(%s : %s %s)${NC}\n" "$desc" "$b" "$BUILD_PHASE" "$(jp "build/$b" '{.status.reason}')"
    FAIL=$((FAIL+1))
    o logs "build/$b" -n "$NS" --tail=15 2>/dev/null | sed 's/^/      /' || true
  fi
}

# ---------------------------------------------------------------------------
# Attentes et requêtes
# ---------------------------------------------------------------------------

# wait_rollout DEPLOYMENT [TIMEOUT_S] [PROJET] : attend la fin du déploiement.
wait_rollout() {
  local name="$1" timeout="${2:-180}" ns="${3:-$NS}"
  if o rollout status "deployment/$name" -n "$ns" --timeout="${timeout}s" >/dev/null 2>&1; then
    ok "Deployment $name disponible"
  else
    ko "Deployment $name pas disponible après ${timeout}s"
    debug_pods "$ns"
  fi
}

# jp RESSOURCE EXPRESSION_JSONPATH [PROJET] : lit un champ (vide si absent).
jp() { o get "$1" -n "${3:-$NS}" -o "jsonpath=$2" 2>/dev/null || true; }

# route_url ROUTE : https://… ou http://… selon que la Route porte du TLS.
route_url() {
  local host tls
  host="$(jp "route/$1" '{.spec.host}')"
  [ -n "$host" ] || return 1
  tls="$(jp "route/$1" '{.spec.tls.termination}')"
  if [ -n "$tls" ]; then printf 'https://%s' "$host"; else printf 'http://%s' "$host"; fi
}

# route_get ROUTE CHEMIN : requête depuis VOTRE poste, à travers le routeur,
# comme un navigateur. -k : le certificat d'un cluster de test est rarement
# reconnu par le poste. Échoue si le code HTTP est 400 ou plus.
route_get() {
  local url
  url="$(route_url "$1")" || return 1
  curl -sS -k -f -m 5 "$url$2" 2>/dev/null
}

# route_code ROUTE CHEMIN : seulement le code HTTP (000 si injoignable).
route_code() {
  local url
  url="$(route_url "$1")" || { printf '000'; return 0; }
  curl -s -k -o /dev/null -m 5 -w '%{http_code}' "$url$2" 2>/dev/null || true
}

# wait_route_http ROUTE CHEMIN [TIMEOUT_S] : attend une réponse 2xx par la Route.
wait_route_http() {
  local r="$1" path="$2" timeout="${3:-90}" i=0
  until route_get "$r" "$path" >/dev/null; do
    i=$((i+2)); sleep 2
    if [ "$i" -ge "$timeout" ]; then
      ko "La Route $r ne répond pas sur $path après ${timeout}s (code $(route_code "$r" "$path"))"
      return 1
    fi
  done
  ok "La Route $r répond sur $path"
}

# svc_get SERVICE PORT CHEMIN [PROJET] : requête HTTP vers un Service, relayée
# par l'API du cluster (pour ce qui n'a pas de Route).
svc_get() {
  o get --raw "/api/v1/namespaces/${4:-$NS}/services/http:$1:$2/proxy$3" --request-timeout=5s 2>/dev/null
}

# wait_svc_http SERVICE PORT CHEMIN [TIMEOUT_S] [PROJET] : attend une réponse 2xx.
wait_svc_http() {
  local svc="$1" port="$2" path="$3" timeout="${4:-90}" ns="${5:-$NS}" i=0
  until svc_get "$svc" "$port" "$path" "$ns" >/dev/null; do
    i=$((i+2)); sleep 2
    if [ "$i" -ge "$timeout" ]; then
      ko "Service $svc:$port$path ne répond pas après ${timeout}s"
      return 1
    fi
  done
  ok "Service $svc:$port$path répond"
}

# champ_json CLÉ : extrait la valeur d'une clé d'un petit document JSON lu sur
# l'entrée standard (chaîne ou nombre), sans dépendre de jq.
champ_json() {
  sed -n "s/.*\"$1\" *: *\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" | head -1
}

# debug_pods [PROJET] : après un échec, affiche ce qu'un développeur regarderait.
debug_pods() {
  local ns="${1:-$NS}"
  warn "Pistes de diagnostic (projet $ns) :"
  o get pods -n "$ns" -o wide 2>/dev/null | sed 's/^/      /' || true
  o get events -n "$ns" --sort-by=.lastTimestamp 2>/dev/null | tail -8 | sed 's/^/      /' || true
}

# Bilan final : code de sortie non nul si au moins un échec
summary() {
  echo "-----------------------------------------"
  if [ "$FAIL" -eq 0 ]; then
    printf "${GREEN}✅ TP validé : %d vérification(s) réussie(s)" "$PASS"
    [ "$SKIP" -gt 0 ] && printf ", %d non vérifiée(s) dans cet environnement" "$SKIP"
    printf ".${NC}\n"
    exit 0
  else
    printf "${RED}❌ TP non validé : %d échec(s) sur %d.${NC}\n" "$FAIL" "$((PASS+FAIL))"
    [ "$MODE" = "jetable" ] && printf "   Relancez avec KEEP=1 pour garder le projet de vérification et l'inspecter.\n"
    exit 1
  fi
}
