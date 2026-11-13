#!/usr/bin/env bash
# Les contrôles statiques, sans cluster : ceux que la CI exécute en premier.
#   ./scripts/lint.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
RC=0
ko() { printf '✗ %s\n' "$*"; RC=1; }
ok() { printf '✓ %s\n' "$*"; }

for tp in tp[0-9][0-9]-*/; do
  tp="${tp%/}"
  [ -x "$tp/verify.sh" ] || ko "$tp : verify.sh absent ou non exécutable"
  [ -f "$tp/README.md" ] || ko "$tp : README.md absent"
  [ -d "$tp/starter" ] && [ -d "$tp/solution" ] || { ko "$tp : starter/ ou solution/ absent"; continue; }
  grep -rq '______' "$tp/starter" || ko "$tp/starter ne contient aucun trou « ______ »"
  if grep -rn '______' "$tp/solution"; then ko "$tp/solution contient encore des trous"; fi
  # Mêmes fichiers des deux côtés : le starter est la solution, trous en plus.
  if ! diff <(cd "$tp/starter" && find . -type f | sort) <(cd "$tp/solution" && find . -type f | sort) >/dev/null; then
    ko "$tp : starter/ et solution/ n'ont pas les mêmes fichiers"
  fi
  # Un starter qui passerait la vérification ne laisserait rien à faire.
  if "$tp/verify.sh" starter >/dev/null 2>&1; then ko "$tp : verify.sh starter réussit"; fi
done
[ "$RC" -eq 0 ] && ok "Structure des TP, trous des starters"

# verify.sh déploie dans un projet qu'il choisit : un namespace en dur le contrarierait.
if grep -rnE '^  namespace:' tp[0-9][0-9]-*/{starter,solution,heritage,pannes,outils} 2>/dev/null; then
  ko "metadata.namespace interdit dans les manifestes des TP"
else ok "Aucun namespace en dur"; fi

if grep -rlI $'\r' --exclude-dir=.git . >/dev/null 2>&1; then
  grep -rlI $'\r' --exclude-dir=.git . ; ko "Fins de ligne Windows"
else ok "Aucune fin de ligne Windows"; fi

for f in tp*/*/depot/.s2i/bin/* tp*/*/*/s2i/bin/* builders/*/s2i/bin/* scripts/*.sh tp*/verify.sh tp*/outils/*.sh tp*/solution/*.sh tp*/starter/*.sh; do
  [ -f "$f" ] && [ ! -x "$f" ] && ko "$f n'est pas exécutable"
done

if python3 -c 'import yaml' 2>/dev/null; then
  if python3 - <<'PY'
import glob, sys, yaml
rc = 0
for f in sorted(glob.glob("tp*/solution/**/*.yaml", recursive=True) + glob.glob("tp*/heritage/*.yaml") + glob.glob("tp*/outils/*.yaml") + glob.glob(".github/workflows/*.yml")):
    try:
        for d in yaml.safe_load_all(open(f, encoding="utf-8")):
            if f.startswith("tp") and d is not None:
                assert d.get("apiVersion") and d.get("kind"), "apiVersion ou kind absent"
                lab = d.get("metadata", {}).get("labels", {})
                assert lab.get("app.kubernetes.io/part-of") in ("telemarche", "telecaisse"), \
                    f"{d['kind']}/{d['metadata']['name']} sans label app.kubernetes.io/part-of"
    except Exception as e:
        print(f"{f}: {e}"); rc = 1
sys.exit(rc)
PY
  then ok "YAML valide, label app.kubernetes.io/part-of partout"; else ko "Manifestes invalides"; fi
else
  echo "○ PyYAML absent : manifestes non contrôlés"
fi

if diff -r builders/telemach-go-builder/s2i tp05-personnaliser-s2i/solution/telemach-go-builder/s2i >/dev/null \
   && diff builders/telemach-go-builder/Dockerfile tp05-personnaliser-s2i/solution/telemach-go-builder/Dockerfile >/dev/null; then
  ok "builders/telemach-go-builder identique à la solution du TP05"
else ko "builders/telemach-go-builder diffère de la solution du TP05"; fi

if command -v shellcheck >/dev/null 2>&1; then
  shopt -s nullglob
  if shellcheck -x -S warning scripts/*.sh tp*/verify.sh tp*/outils/*.sh tp*/solution/*.sh tp*/heritage/*.sh \
       builders/*/test/run builders/*/s2i/bin/* tp*/solution/depot/.s2i/bin/*; then ok "shellcheck"; else ko "shellcheck"; fi
else
  echo "○ shellcheck absent"
fi
exit $RC
