#!/bin/bash
# ============================================================
# AMSTC - Les deux serveurs portent-ils les memes donnees ?
#
#     bash comparer-bases.sh
#
# Compte les lignes de CHAQUE table des schemas public, auth et
# storage, sur les deux serveurs, et compare.
#
# Pourquoi toutes les tables et pas seulement celles qui comptent : le
# 19 novembre, une restauration paraissait complete - 315 comptes bien
# presents - alors que auth.identities etait vide. Personne n'aurait pu
# se connecter. Compter les profils ne l'aurait pas vu.
#
# Une sortie vide est la seule qui vaille.
# ============================================================

set -uo pipefail

ANCIEN="${AMSTC_ANCIEN:-167.233.231.165}"
NOUVEAU="${AMSTC_NOUVEAU:-2.29.182.131}"
CLE="${AMSTC_CLE:-$HOME/.ssh/hetzner_amstc}"
PILES="rffqs8ck1ckdixkuu2xjo5sc qmy744bqv0xnafmr9nndu34t"
S="-i $CLE -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=90"

SQL=$(cat <<'FIN'
select table_schema||'.'||table_name||' = '||
  (xpath('/row/c/text()', query_to_xml(
    'select count(*) as c from '||quote_ident(table_schema)||'.'||quote_ident(table_name),
    false, true, '')))[1]::text::int
from information_schema.tables
where table_schema in ('public','auth','storage') and table_type='BASE TABLE'
order by 1;
FIN
)

ECART=0
for u in $PILES; do
  for h in "$ANCIEN" "$NOUVEAU"; do
    printf '%s\n' "$SQL" \
      | ssh $S "root@$h" "docker exec -i supabase-db-$u psql -U supabase_admin -d postgres -tA" \
        > "/tmp/cmp-$u-$h.txt" 2>/dev/null
  done
  n=$(grep -c . "/tmp/cmp-$u-$ANCIEN.txt" 2>/dev/null || echo 0)
  if [ "$n" -lt 1 ]; then
    echo "  ${u:0:8} : LECTURE IMPOSSIBLE sur l'ancien serveur"
    ECART=1
    continue
  fi
  if diff -q "/tmp/cmp-$u-$ANCIEN.txt" "/tmp/cmp-$u-$NOUVEAU.txt" >/dev/null 2>&1; then
    echo "  ${u:0:8} : identiques sur $n tables"
  else
    echo "  ${u:0:8} : ECARTS ( < ancien, > nouveau )"
    diff "/tmp/cmp-$u-$ANCIEN.txt" "/tmp/cmp-$u-$NOUVEAU.txt" | grep -E '^[<>]' | sed 's/^/      /'
    ECART=1
  fi
done

echo ""
if [ "$ECART" -eq 0 ]; then
  echo "  Les deux serveurs portent les memes donnees. Bascule possible."
else
  echo "  NE BASCULEZ PAS. Relancez synchroniser-avant-bascule.sh."
fi
exit $ECART
