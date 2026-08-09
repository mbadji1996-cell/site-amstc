#!/bin/bash
# ============================================================
# AMSTC - Sauvegarde quotidienne du VPS
#
# Sauvegarde les DEUX instances Supabase auto-hébergées (amstc et
# consultations) : bases de données complètes + fichiers du Storage
# (photos des membres, pièces jointes).
#
# Les conteneurs sont DÉCOUVERTS automatiquement : aucun identifiant
# n'est écrit en dur, la sauvegarde continue donc de fonctionner si
# Coolify recrée un service avec un nouvel identifiant.
#
# Installation : voir README-sauvegardes.md
# Vérification à blanc : bash sauvegarde-vps.sh --test
# ============================================================

set -uo pipefail

DEST="${AMSTC_BACKUP_DIR:-/var/backups/amstc}"
RETENTION_JOURS="${AMSTC_BACKUP_RETENTION:-14}"

# Destination distante (rsync). Vide = sauvegarde locale seulement.
# Exemple Hetzner Storage Box : u123456@u123456.your-storagebox.de:amstc/
DISTANT="${AMSTC_BACKUP_REMOTE:-}"

DATE=$(date +%Y-%m-%d_%H%M)
JOURNAL="${DEST}/sauvegarde.log"
MODE_TEST=0
[ "${1:-}" = "--test" ] && MODE_TEST=1

dire() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Toute la sortie part aussi dans le journal (sauf en mode test, où on
# veut simplement lire le résultat à l'écran).
if [ "$MODE_TEST" -eq 0 ]; then
  mkdir -p "$DEST"
  exec > >(tee -a "$JOURNAL") 2>&1
fi

dire "=== Sauvegarde AMSTC ($([ "$MODE_TEST" -eq 1 ] && echo 'MODE TEST' || echo 'réelle')) ==="

CONTENEURS_DB=$(docker ps --format '{{.Names}}' | grep '^supabase-db-' || true)
CONTENEURS_ST=$(docker ps --format '{{.Names}}' | grep '^supabase-storage-' || true)

if [ -z "$CONTENEURS_DB" ]; then
  dire "ERREUR : aucun conteneur supabase-db-* en cours d'exécution."
  dire "Conteneurs visibles :"
  docker ps --format '  {{.Names}}'
  exit 1
fi

dire "Bases trouvées   : $(echo "$CONTENEURS_DB" | tr '\n' ' ')"
dire "Storage trouvés  : $(echo "$CONTENEURS_ST" | tr '\n' ' ')"

if [ "$MODE_TEST" -eq 1 ]; then
  dire "--- Vérification des accès (aucun fichier écrit) ---"
  for C in $CONTENEURS_DB; do
    PW=$(docker exec "$C" printenv POSTGRES_PASSWORD 2>/dev/null || true)
    if [ -z "$PW" ]; then
      dire "  $C : ECHEC - POSTGRES_PASSWORD introuvable dans le conteneur"
      continue
    fi
    TAILLE=$(docker exec -e PGPASSWORD="$PW" "$C" \
      psql -U supabase_admin -h 127.0.0.1 -d postgres -tAc \
      "select pg_size_pretty(pg_database_size('postgres'))" 2>/dev/null || echo "ECHEC")
    dire "  $C : base postgres = $TAILLE"
  done
  for C in $CONTENEURS_ST; do
    N=$(docker exec "$C" sh -c 'find /var/lib/storage -type f 2>/dev/null | wc -l' || echo "ECHEC")
    dire "  $C : $N fichiers dans /var/lib/storage"
  done
  dire "Espace disque disponible : $(df -h / | awk 'NR==2{print $4}')"
  dire "--- Fin du test. Si tout est lisible ci-dessus, la sauvegarde réelle fonctionnera. ---"
  exit 0
fi

ECHECS=0

# ---------- Bases de données ----------
for C in $CONTENEURS_DB; do
  UUID=${C#supabase-db-}
  FICHIER="${DEST}/${DATE}_${UUID}_base.sql.gz"
  dire "Dump de $C ..."

  PW=$(docker exec "$C" printenv POSTGRES_PASSWORD 2>/dev/null || true)
  if [ -z "$PW" ]; then
    dire "  ECHEC : mot de passe Postgres introuvable dans $C"
    ECHECS=$((ECHECS + 1))
    continue
  fi

  # pg_dumpall : rôles et bases comprises, pour une restauration complète.
  if docker exec -e PGPASSWORD="$PW" "$C" \
       pg_dumpall -U supabase_admin -h 127.0.0.1 2>/dev/null | gzip > "$FICHIER"; then
    # Un dump interrompu produit un fichier tronqué mais un code de retour 0
    # côté gzip : on vérifie donc que l'archive se relit et se termine bien.
    if gzip -t "$FICHIER" 2>/dev/null && zcat "$FICHIER" | tail -5 | grep -q "PostgreSQL database cluster dump complete"; then
      dire "  OK : $(du -h "$FICHIER" | cut -f1)"
    else
      dire "  ECHEC : dump incomplet ou illisible, fichier supprimé"
      rm -f "$FICHIER"
      ECHECS=$((ECHECS + 1))
    fi
  else
    dire "  ECHEC : pg_dumpall a renvoyé une erreur"
    rm -f "$FICHIER"
    ECHECS=$((ECHECS + 1))
  fi
done

# ---------- Fichiers du Storage (photos des membres) ----------
for C in $CONTENEURS_ST; do
  UUID=${C#supabase-storage-}
  FICHIER="${DEST}/${DATE}_${UUID}_fichiers.tar.gz"
  dire "Archive des fichiers de $C ..."
  if docker exec "$C" tar czf - -C /var/lib/storage . > "$FICHIER" 2>/dev/null && gzip -t "$FICHIER" 2>/dev/null; then
    dire "  OK : $(du -h "$FICHIER" | cut -f1)"
  else
    dire "  ECHEC : archive des fichiers illisible, supprimée"
    rm -f "$FICHIER"
    ECHECS=$((ECHECS + 1))
  fi
done

# ---------- Copie hors du serveur ----------
# Sans cette étape, une panne matérielle du VPS emporte aussi les
# sauvegardes : c'est le seul scénario réellement irréversible.
if [ -n "$DISTANT" ]; then
  dire "Envoi vers $DISTANT ..."
  if rsync -a --delete -e "ssh -p ${AMSTC_BACKUP_PORT:-23} -o StrictHostKeyChecking=accept-new" \
       "$DEST/" "$DISTANT" 2>&1; then
    dire "  OK"
  else
    dire "  ECHEC : la copie hors serveur n'a pas abouti"
    ECHECS=$((ECHECS + 1))
  fi
else
  dire "ATTENTION : aucune destination distante configurée (AMSTC_BACKUP_REMOTE)."
  dire "Les sauvegardes ne survivraient pas à une panne du VPS."
fi

# ---------- Rotation ----------
find "$DEST" -name '*.sql.gz' -mtime "+${RETENTION_JOURS}" -delete 2>/dev/null
find "$DEST" -name '*.tar.gz' -mtime "+${RETENTION_JOURS}" -delete 2>/dev/null

dire "Sauvegardes présentes : $(ls -1 "$DEST"/*.gz 2>/dev/null | wc -l) fichiers, $(du -sh "$DEST" 2>/dev/null | cut -f1)"

if [ "$ECHECS" -gt 0 ]; then
  dire "=== TERMINE AVEC $ECHECS ECHEC(S) ==="
  exit 1
fi
dire "=== Sauvegarde terminée sans erreur ==="
