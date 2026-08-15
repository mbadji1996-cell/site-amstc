#!/bin/bash
# ============================================================
# Compare les fonctions Edge DÉPLOYÉES sur le VPS à celles du dépôt.
#
# POURQUOI. Une fonction Edge déployée ne se met pas à jour toute seule :
# le dépôt et le VPS divergent sans que rien ne le signale, et l'on ne
# s'en aperçoit qu'au moment où l'on comptait sur la fonction. C'est
# arrivé le 15/08/2026 sur notify-membre, en retard d'un commit - ses
# messages seraient partis sans la signature ©AMSTC, et personne ne
# l'aurait su avant novembre.
#
# La comparaison se fait sur l'EMPREINTE du contenu, pas sur le nombre
# de lignes : deux fichiers peuvent avoir le même nombre de lignes et
# des contenus différents.
#
# Usage, depuis le VPS :
#   curl -fsSL https://raw.githubusercontent.com/mbadji1996-cell/site-amstc/main/supabase/verifier-fonctions.sh | bash
#
# Sortie : une ligne par fonction, et la commande de mise à jour toute
# prête pour celles qui sont en retard.
# ============================================================

set -u

UUID="${AMSTC_SUPABASE_UUID:-rffqs8ck1ckdixkuu2xjo5sc}"
BASE="/data/coolify/services/$UUID/volumes/functions"
DEPOT="https://raw.githubusercontent.com/mbadji1996-cell/site-amstc/main/supabase/functions"

# La liste vient du dépôt lui-même : une fonction ajoutée plus tard sera
# contrôlée sans qu'il faille modifier ce script.
FONCTIONS="admin-reset-link declencher-apercus notify-admin notify-members-whatsapp notify-membre provision-consultation-user sante sync-consultation-password telegram-webhook"

echo "Fonctions Edge - dépôt contre VPS"
echo "---------------------------------"

retard=""
for f in $FONCTIONS; do
  local_f="$BASE/$f/index.ts"

  distant=$(curl -fsSL "$DEPOT/$f/index.ts" 2>/dev/null | sha256sum 2>/dev/null | cut -c1-12)
  if [ -z "$distant" ]; then
    printf '  %-28s introuvable dans le dépôt (ignorée)\n' "$f"
    continue
  fi

  if [ ! -f "$local_f" ]; then
    printf '  %-28s NON DÉPLOYÉE\n' "$f"
    retard="$retard $f"
    continue
  fi

  vps=$(sha256sum "$local_f" | cut -c1-12)
  if [ "$vps" = "$distant" ]; then
    printf '  %-28s à jour\n' "$f"
  else
    printf '  %-28s EN RETARD (vps %s, dépôt %s)\n' "$f" "$vps" "$distant"
    retard="$retard $f"
  fi
done

echo
if [ -z "$retard" ]; then
  echo "Tout est aligné."
  exit 0
fi

echo "À mettre à jour :$retard"
echo
echo "Commande, à copier telle quelle :"
echo
for f in $retard; do
  echo "D=$BASE/$f && mkdir -p \$D && curl -fsSL $DEPOT/$f/index.ts -o \$D/index.ts && echo '$f mis à jour'"
done
echo
echo "Aucun redémarrage n'est nécessaire : le code est relu à chaque appel."
