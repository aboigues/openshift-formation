#!/usr/bin/env bash
# Installe le runner GitHub Actions « okd » sur le poste qui fait tourner CRC :
# c'est lui qui exécute le workflow .github/workflows/okd.yml. Voir docs/gate-okd.md.
#   ./scripts/installer-runner-okd.sh            # installe, enregistre, démarre le service
#   ./scripts/installer-runner-okd.sh --retirer  # arrête, désenregistre, supprime
# Prérequis : Linux (WSL avec systemd), gh connecté avec les droits d'administration
# du dépôt, sudo (pour le service systemd).
set -euo pipefail

VERSION_RUNNER="2.338.2"
SHA256_RUNNER="baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40"
DEPOT="aboigues/openshift-formation"
DOSSIER="${DOSSIER_RUNNER:-$HOME/actions-runner-okd}"
NOM="okd-$(hostname)"

die() { printf '✗ %s\n' "$*" >&2; exit 1; }
ok()  { printf '✓ %s\n' "$*"; }

command -v gh >/dev/null || die "gh introuvable."
gh auth status >/dev/null 2>&1 || die "gh n'est pas connecté : gh auth login."
[ "$(ps -p 1 -o comm=)" = systemd ] || die "systemd n'est pas actif (WSL : [boot] systemd=true dans /etc/wsl.conf)."

jeton() { gh api -X POST "repos/$DEPOT/actions/runners/$1" --jq .token; }

if [ "${1:-}" = "--retirer" ]; then
  [ -d "$DOSSIER" ] || die "Aucun runner dans $DOSSIER."
  cd "$DOSSIER"
  sudo ./svc.sh stop || true
  sudo ./svc.sh uninstall || true
  ./config.sh remove --token "$(jeton remove-token)"
  cd / && rm -rf "$DOSSIER"
  ok "Runner $NOM retiré."
  exit 0
fi

# Le cluster est-il joignable comme le workflow l'attend ?
if curl -sk -m 5 https://api.crc.testing:6443/healthz | grep -qx ok; then
  ok "OKD répond sur https://api.crc.testing:6443"
else
  printf '⚠ OKD ne répond pas sur https://api.crc.testing:6443 : CRC arrêté, ou WSL pas en réseau miroir (docs/gate-okd.md).\n'
fi

[ -e "$DOSSIER/.runner" ] && die "Un runner est déjà configuré dans $DOSSIER (--retirer d'abord)."
mkdir -p "$DOSSIER" && cd "$DOSSIER"
archive="actions-runner-linux-x64-${VERSION_RUNNER}.tar.gz"
curl -fsSLO "https://github.com/actions/runner/releases/download/v${VERSION_RUNNER}/${archive}"
echo "${SHA256_RUNNER}  ${archive}" | sha256sum -c - >/dev/null || die "Somme SHA-256 du runner incorrecte."
tar -xzf "$archive" && rm -f "$archive"
ok "Runner ${VERSION_RUNNER} téléchargé et vérifié dans $DOSSIER"

./config.sh --unattended --replace \
  --url "https://github.com/$DEPOT" --token "$(jeton registration-token)" \
  --name "$NOM" --labels okd --work _work
ok "Runner enregistré : $NOM (label okd)"

sudo ./svc.sh install "$USER"
sudo ./svc.sh start
ok "Service démarré : il se relance avec WSL."
gh api "repos/$DEPOT/actions/runners" --jq '.runners[] | "  \(.name) : \(.status) [\([.labels[].name] | join(", "))]"'
