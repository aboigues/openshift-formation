#!/usr/bin/env bash
# Les contrôles de sécurité, sans cluster. La CI les exécute (job « securite ») ;
# en local, il faut docker ou podman.
#   ./scripts/securite.sh
#
#   1. Secrets : aucun identifiant ni clé dans le dépôt.
#   2. Manifestes et Dockerfile : aucune faute de configuration HIGH ou CRITICAL
#      dans ce qui est déployé (solution/, outils/, apps/, builders/). Les
#      dossiers heritage/ et pannes/ sont fautifs exprès : ils ne sont pas scannés.
#   3. Code Go : aucune vulnérabilité atteignable dans une dépendance. Celles de
#      la bibliothèque standard dépendent de l image go-toolset de Red Hat :
#      elles sont signalées, sans bloquer.
#   4. Images : aucune vulnérabilité HIGH ou CRITICAL corrigeable dans les
#      images de Télémarché.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
MOTEUR="${MOTEUR:-$(command -v docker || command -v podman || true)}"
[ -n "$MOTEUR" ] || { echo "ni docker ni podman" >&2; exit 1; }
TRIVY_IMAGE="${TRIVY_IMAGE:-docker.io/aquasec/trivy:0.76.2}"
GO_IMAGE="registry.access.redhat.com/ubi10/go-toolset:10.3"
GOVULNCHECK="golang.org/x/vuln/cmd/govulncheck@v1.9.0"
RC=0
ko() { printf "✗ %s\n" "$*"; RC=1; }
ok() { printf "✓ %s\n" "$*"; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
trivy() { "$MOTEUR" run --rm -v "$tmp":/w:ro -v trivy-cache:/root/.cache "$TRIVY_IMAGE" "$@"; }

# Ce qui est versionné, sans .git ni ce qui est fautif exprès.
mkdir "$tmp/depot" "$tmp/config"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files -co --exclude-standard -z | tar --null --ignore-failed-read -T - -cf - 2>/dev/null | tar -xf - -C "$tmp/depot"
else
  tar --exclude=.git -cf - . | tar -xf - -C "$tmp/depot"
fi
for d in tp[0-9][0-9]-*/solution tp[0-9][0-9]-*/outils apps builders; do
  [ -d "$d" ] && mkdir -p "$tmp/config/$(dirname "$d")" && cp -R "$d" "$tmp/config/$d"
done
chmod -R a+rX "$tmp"

if trivy fs --quiet --scanners secret --exit-code 1 /w/depot; then ok "Aucun secret dans le dépôt"; else ko "Secret détecté dans le dépôt"; fi

if trivy config --quiet --severity HIGH,CRITICAL --exit-code 1 /w/config; then
  ok "Manifestes et Dockerfile : 0 faute HIGH/CRITICAL"
else ko "Manifestes ou Dockerfile : fautes HIGH/CRITICAL"; fi

"$MOTEUR" run --rm -u 0 -v "$tmp/depot/apps":/apps:ro "$GO_IMAGE" sh -c "
  cp -r /apps /tmp/apps && for a in telemarche bonjour; do
    cd /tmp/apps/\$a && go run $GOVULNCHECK -format json ./... || exit 9
  done" > "$tmp/vuln.json" 2>"$tmp/vuln.err" || { tail -5 "$tmp/vuln.err"; ko "govulncheck n a pas pu tourner"; }
if command -v jq >/dev/null 2>&1; then
  # Seules comptent les vulnérabilités dont le code APPELLE la fonction fautive.
  atteintes="$(jq -r "select(.finding != null) | .finding | select(.trace[0].function != null) | \"\(.osv) \(.trace[0].module)\"" "$tmp/vuln.json" | sort -u)"
  std="$(printf "%s\n" "$atteintes" | awk "\$2==\"stdlib\"{print \$1}" | xargs)"
  deps="$(printf "%s\n" "$atteintes" | awk "NF && \$2!=\"stdlib\"" | xargs)"
  if [ -n "$std" ]; then
    echo "⚠ Bibliothèque standard de Go (image go-toolset) : $std"
    [ -n "${GITHUB_ACTIONS:-}" ] && echo "::warning::Vulnérabilités de la bibliothèque standard de Go, en attente d une image go-toolset corrigée : $std"
  fi
  if [ -n "$deps" ]; then ko "Vulnérabilités atteignables dans les dépendances Go : $deps"; else ok "Dépendances Go : aucune vulnérabilité atteignable"; fi
else
  echo "○ jq absent : résultat de govulncheck non analysé"
fi

for c in api web; do
  if "$MOTEUR" build -q -f "apps/telemarche/Dockerfile.$c" -t "telemarche-$c:securite" apps/telemarche >/dev/null \
     && "$MOTEUR" save -o "$tmp/$c.tar" "telemarche-$c:securite" >/dev/null && chmod a+r "$tmp/$c.tar" \
     && trivy image --quiet --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --input "/w/$c.tar"; then
    ok "Image $c : 0 vulnérabilité HIGH/CRITICAL corrigeable"
  else ko "Image $c : vulnérabilités HIGH/CRITICAL corrigeables, ou construction impossible"; fi
done
exit $RC
