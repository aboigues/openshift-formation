#!/usr/bin/env bash
# Rejoue tous les TP sur le cluster auquel oc est connecté : verify.sh solution
# doit réussir. C'est la répétition générale avant une session, et le job
# « cluster » de la CI.
#   ./scripts/test-all.sh                 # tous les TP
#   ./scripts/test-all.sh tp02 tp04       # seulement ceux-là
# OUI=1 est posé d'office : sur un cluster sans création de projet, les objets
# des TP du projet courant sont supprimés. HERITAGE=1 contrôle aussi les prémisses.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export OUI=1 HERITAGE="${HERITAGE:-1}"
BILAN=(); RC=0
for tp in tp[0-9][0-9]-*/; do
  tp="${tp%/}"
  if [ "$#" -gt 0 ]; then case " $* " in *" ${tp%%-*} "*) ;; *) continue ;; esac; fi
  echo; echo "════════ $tp"
  debut=$SECONDS
  if "./$tp/verify.sh" solution; then BILAN+=("✅ $tp ($((SECONDS-debut)) s)"); else BILAN+=("❌ $tp ($((SECONDS-debut)) s)"); RC=1; fi
done
echo; echo "════════ Bilan"; printf '%s\n' "${BILAN[@]}"
exit $RC
