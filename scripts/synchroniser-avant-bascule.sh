#!/bin/bash
# ============================================================
# AMSTC - Remise a niveau du nouveau serveur, juste avant la bascule
#
# À lancer DEPUIS VOTRE POSTE :
#
#     bash synchroniser-avant-bascule.sh
#
# POURQUOI. Le nouveau serveur a recu une copie des donnees le 19
# novembre a 18 h. L'ancien, lui, continue de vivre : connexions des
# membres, messages WhatsApp, saisies de consultations. Basculer le DNS
# sans remise a niveau perdrait tout ce qui s'est produit entre les
# deux.
#
# CE QU'IL FAIT. Il ne cherche pas a deviner ce qui a change : il
# refait la copie en entier. Trente mégaoctets, deux minutes, et aucun
# risque d'oublier une table. Le delta serait plus rapide et bien plus
# facile a se tromper.
#
# LA FENETRE. Entre l'arret de Kong sur l'ancien serveur et la bascule
# du DNS, les deux API ne repondent plus - comptez cinq minutes. Meta
# reessaie les webhooks WhatsApp non delivres, donc aucun message n'est
# perdu ; les membres connectes verront une erreur passagere.
# ============================================================

set -uo pipefail

ANCIEN="${AMSTC_ANCIEN:-167.233.231.165}"
NOUVEAU="${AMSTC_NOUVEAU:-2.29.182.131}"
CLE="${AMSTC_CLE:-$HOME/.ssh/hetzner_amstc}"
PILES="rffqs8ck1ckdixkuu2xjo5sc qmy744bqv0xnafmr9nndu34t"

S="-i $CLE -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=60"
dire() { echo "[$(date +%H:%M:%S)] $*"; }

dire "=== 1. Arret des passerelles sur l'ancien serveur ==="
dire "    (les API cessent de repondre a partir de maintenant)"
for u in $PILES; do
  ssh $S "root@$ANCIEN" "docker stop supabase-kong-$u" 2>&1 | sed 's/^/      /'
done

dire "=== 2. Dumps frais ==="
for u in $PILES; do
  ssh $S "root@$ANCIEN" "docker exec supabase-db-$u pg_dumpall -U supabase_admin -h 127.0.0.1 2>/dev/null | gzip > /tmp/final-$u.sql.gz && du -h /tmp/final-$u.sql.gz" \
    2>&1 | sed "s/^/      $u : /"
done

dire "=== 3. Transfert direct entre serveurs ==="
for u in $PILES; do
  ssh $S "root@$ANCIEN" \
    "K=\$(cat /tmp/cle-transfert); scp -q -i \$K -o BatchMode=yes -o StrictHostKeyChecking=accept-new /tmp/final-$u.sql.gz root@$NOUVEAU:/tmp/$u.sql.gz" \
    2>&1 | sed 's/^/      /'
done

dire "=== 4. Fichiers du Storage (delta seulement) ==="
ssh $S "root@$ANCIEN" \
  "K=\$(cat /tmp/cle-transfert); rsync -a --delete -e \"ssh -i \$K -o BatchMode=yes -o StrictHostKeyChecking=accept-new\" /data/coolify/services/ root@$NOUVEAU:/data/coolify/services/ 2>&1 | tail -2" \
  2>&1 | sed 's/^/      /'

dire "=== 5. Remise a zero et restauration sur le nouveau serveur ==="
for u in $PILES; do
  dire "    $u"
  # On repart d'une base vide : restaurer par-dessus l'existant
  # provoquerait les memes conflits de cles etrangeres qu'au premier
  # essai, et laisserait des tables a moitie remplies.
  ssh $S "root@$NOUVEAU" "
    docker stop supabase-db-$u >/dev/null 2>&1
    docker rm -f supabase-db-$u >/dev/null 2>&1
    docker volume rm ${u}_supabase-db-data >/dev/null 2>&1
    cd /data/coolify/services/$u && docker compose up -d --no-deps supabase-db >/dev/null 2>&1
    for i in \$(seq 1 40); do
      [ \"\$(docker inspect -f '{{.State.Health.Status}}' supabase-db-$u 2>/dev/null)\" = healthy ] && break
      sleep 3
    done
    gunzip -c /tmp/$u.sql.gz | docker exec -i supabase-db-$u psql -U supabase_admin -d postgres > /tmp/log-$u.txt 2>&1
    echo \"      erreurs de restauration : \$(grep -c '^ERROR' /tmp/log-$u.txt)\"
  " 2>&1 | sed 's/^/      /'

  # Les tables auth refusees pour cle etrangere, rejouees dans l'ordre.
  ssh $S "root@$NOUVEAU" "bash /tmp/ra.sh $u 2>/dev/null | grep -vE 'awk:|^COPY 0'" 2>&1 | sed 's/^/      /'

  # Le reglage memoire ne survit pas a la suppression du volume.
  ssh $S "root@$NOUVEAU" "bash /tmp/rp.sh $u" 2>&1 | sed 's/^/      /'
done

dire "=== 6. Redemarrage des services ==="
for u in $PILES; do
  ssh $S "root@$NOUVEAU" "cd /data/coolify/services/$u && docker compose up -d --no-deps supabase-auth supabase-rest supabase-storage supabase-edge-functions supabase-kong >/dev/null 2>&1" 2>&1
done
sleep 15

dire "=== 7. Controle ==="
ssh $S "root@$NOUVEAU" "docker ps --filter health=unhealthy --format '      EN DEFAUT : {{.Names}}'" 2>&1
ssh $S "root@$NOUVEAU" "free -m | awk '/Mem:/{printf \"      memoire : %s Mo utilises sur %s\n\", \$3, \$2}'" 2>&1

echo ""
dire "=== PRET POUR LA BASCULE ==="
dire "Comparez les deux bases avant de changer le DNS :"
dire "   bash scripts/comparer-bases.sh"
dire ""
dire "L'ancien serveur a ses passerelles ARRETEES. Si vous renoncez a"
dire "basculer, relancez-les :"
for u in $PILES; do
  dire "   ssh root@$ANCIEN 'docker start supabase-kong-$u'"
done
