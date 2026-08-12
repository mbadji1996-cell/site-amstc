#!/bin/bash
# ============================================================
# AMSTC - Sauvegarde quotidienne du VPS
#
# Sauvegarde TOUTES les bases Postgres du serveur, pas seulement celles
# de l'AMSTC :
#   - supabase-db-*   les deux instances Supabase (amstc, consultations)
#   - db-*            les bases des autres applications déployées par
#                     Coolify (sontencare.com et suivantes)
#   - coolify-db      la configuration de Coolify elle-même - elle
#                     contient les VARIABLES D'ENVIRONNEMENT de tous les
#                     services, qui n'existent nulle part ailleurs : sans
#                     elle, il faudrait tout reconfigurer à la main.
#
# Plus les fichiers du Storage Supabase (photos des membres, pièces
# jointes).
#
# Les conteneurs sont DÉCOUVERTS automatiquement : aucun identifiant
# n'est écrit en dur, la sauvegarde continue donc de fonctionner si
# Coolify recrée un service avec un nouvel identifiant, et une nouvelle
# application déployée est prise en compte sans rien modifier ici.
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

CONTENEURS_DB=$(docker ps --format '{{.Names}}' \
  | grep -E '^(supabase-db-|db-|coolify-db$)' || true)
CONTENEURS_ST=$(docker ps --format '{{.Names}}' | grep '^supabase-storage-' || true)

if [ -z "$CONTENEURS_DB" ]; then
  dire "ERREUR : aucun conteneur de base de données trouvé."
  dire "Conteneurs visibles :"
  docker ps --format '  {{.Names}}'
  exit 1
fi

dire "Bases trouvées   : $(echo "$CONTENEURS_DB" | tr '\n' ' ')"
dire "Storage trouvés  : $(echo "$CONTENEURS_ST" | tr '\n' ' ')"

# Identifiant de connexion propre à chaque conteneur.
#
# Supabase impose supabase_admin : son POSTGRES_USER vaut « postgres »,
# un rôle qui n'a pas les droits suffisants pour un pg_dumpall complet.
# Les autres conteneurs annoncent leur utilisateur dans POSTGRES_USER
# (« coolify » pour coolify-db, souvent « postgres » ailleurs) : le lire
# évite d'écrire en dur un identifiant qui changerait au prochain
# déploiement.
utilisateur_de() {
  case "$1" in
    supabase-db-*) echo "supabase_admin" ;;
    *) docker exec "$1" printenv POSTGRES_USER 2>/dev/null || echo "postgres" ;;
  esac
}

# Nom court et lisible pour le fichier produit : l'identifiant Coolify
# seul ne dit rien de ce que l'archive contient.
etiquette_de() {
  case "$1" in
    coolify-db) echo "coolify-config" ;;
    supabase-db-*) echo "supabase-${1#supabase-db-}" ;;
    db-*) echo "app-${1#db-}" ;;
    *) echo "$1" ;;
  esac
}

if [ "$MODE_TEST" -eq 1 ]; then
  dire "--- Vérification des accès (aucun fichier écrit) ---"
  for C in $CONTENEURS_DB; do
    PW=$(docker exec "$C" printenv POSTGRES_PASSWORD 2>/dev/null || true)
    if [ -z "$PW" ]; then
      dire "  $C : ECHEC - POSTGRES_PASSWORD introuvable dans le conteneur"
      continue
    fi
    U=$(utilisateur_de "$C")
    # La taille du CLUSTER, pas d'une base nommée : chaque application a
    # la sienne (« plateforme_sanitaire », « coolify »…), et interroger
    # « postgres » en dur afficherait 8 Mo pour une base pleine.
    TAILLE=$(docker exec -e PGPASSWORD="$PW" "$C" \
      psql -U "$U" -h 127.0.0.1 -d postgres -tAc \
      "select pg_size_pretty(sum(pg_database_size(datname))) from pg_database" 2>/dev/null || echo "ECHEC")
    dire "  $C : utilisateur $U, total des bases = ${TAILLE:-ECHEC}  -> $(etiquette_de "$C")"
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
  FICHIER="${DEST}/${DATE}_$(etiquette_de "$C")_base.sql.gz"
  dire "Dump de $C ..."

  PW=$(docker exec "$C" printenv POSTGRES_PASSWORD 2>/dev/null || true)
  if [ -z "$PW" ]; then
    dire "  ECHEC : mot de passe Postgres introuvable dans $C"
    ECHECS=$((ECHECS + 1))
    continue
  fi
  U=$(utilisateur_de "$C")

  # pg_dumpall : rôles et bases comprises, pour une restauration complète.
  if docker exec -e PGPASSWORD="$PW" "$C" \
       pg_dumpall -U "$U" -h 127.0.0.1 2>/dev/null | gzip > "$FICHIER"; then
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
  FICHIER="${DEST}/${DATE}_supabase-${UUID}_fichiers.tar.gz"
  dire "Archive des fichiers de $C ..."
  # Une archive vide se relit parfaitement : sans ce compte, un Storage
  # devenu illisible passerait pour sauvegardé.
  N=$(docker exec "$C" sh -c 'find /var/lib/storage -type f 2>/dev/null | wc -l' 2>/dev/null || echo 0)
  if docker exec "$C" tar czf - -C /var/lib/storage . > "$FICHIER" 2>/dev/null \
     && gzip -t "$FICHIER" 2>/dev/null && [ "${N:-0}" -gt 0 ]; then
    dire "  OK : $(du -h "$FICHIER" | cut -f1) ($N fichiers)"
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

  # La clé dédiée doit être NOMMÉE explicitement : elle ne porte pas un
  # des noms que ssh essaie d'office (id_rsa, id_ed25519). Sans -i, la
  # copie échouerait chaque nuit en réclamant un mot de passe que
  # personne n'est là pour saisir.
  CLE="${AMSTC_BACKUP_KEY:-/root/.ssh/storagebox}"
  OPTIONS_SSH="-p ${AMSTC_BACKUP_PORT:-23} -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
  if [ -f "$CLE" ]; then
    # IdentitiesOnly : sans cela ssh présente d'abord toutes les clés du
    # serveur, et la Storage Box coupe la connexion après quelques essais
    # infructueux - la bonne clé n'est alors jamais atteinte.
    OPTIONS_SSH="$OPTIONS_SSH -i $CLE -o IdentitiesOnly=yes"
  else
    dire "  (pas de clé $CLE : on s'en remet aux clés par défaut)"
  fi

  # BatchMode interdit toute invite : en cas de problème la copie échoue
  # franchement au lieu de rester bloquée jusqu'au prochain redémarrage.
  if rsync -a --delete -e "ssh $OPTIONS_SSH" \
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
