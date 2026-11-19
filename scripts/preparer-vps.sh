#!/bin/bash
# ============================================================
# AMSTC - Mise en condition d'un VPS neuf, avant Coolify
#
# À lancer sur le NOUVEAU serveur, une seule fois :
#
#     bash preparer-vps.sh
#
# Le script est idempotent : le relancer ne casse rien et ne duplique
# rien. Il s'arrête à la première erreur plutôt que de continuer sur
# une base bancale.
#
# Il ne touche NI à Docker, NI à Coolify, NI aux données : il se
# contente de rendre la machine habitable. L'installation de Coolify
# reste une étape explicite, pour qu'on voie ce qu'on exécute.
# ============================================================

set -euo pipefail

dire() { echo "[$(date '+%H:%M:%S')] $*"; }

[ "$(id -u)" -eq 0 ] || { echo "À lancer en root."; exit 1; }

dire "=== Machine ==="
dire "  $(. /etc/os-release; echo "$PRETTY_NAME") - $(nproc) vCPU - $(free -m | awk '/Mem:/{print $2}') Mo"
dire "  datacenter : $(curl -s --max-time 8 http://169.254.169.254/hetzner/v1/metadata/availability-zone || echo inconnu)"

# ---------- Fuseau ----------
# Les journaux et l'heure des sauvegardes doivent se lire sans calcul
# mental ; le cron de 3 h doit être 3 h à Dakar.
if [ "$(timedatectl show -p Timezone --value)" != "Africa/Dakar" ]; then
  timedatectl set-timezone Africa/Dakar
  dire "fuseau réglé sur Africa/Dakar"
else
  dire "fuseau déjà sur Africa/Dakar"
fi

# ---------- Mises à jour ----------
dire "mise à jour des paquets ..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq rsync curl ca-certificates >/dev/null
dire "  fait"

# ---------- Fichier d'échange ----------
# Deux gigaoctets de mémoire, c'est peu : le swap n'est pas là pour
# travailler, mais pour que les pages froides aient où aller plutôt que
# de déclencher le tueur de processus. swappiness bas : on n'y recourt
# qu'en dernier ressort.
if swapon --show | grep -q '/swapfile'; then
  dire "fichier d'échange déjà actif ($(swapon --show=SIZE --noheadings | head -1))"
else
  dire "création du fichier d'échange (2 Go) ..."
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  dire "  fait"
fi
sysctl -q -w vm.swappiness=10
echo 'vm.swappiness=10' > /etc/sysctl.d/99-amstc-swap.conf

# ---------- Pare-feu ----------
# Seuls trois ports ont une raison d'être ouverts. Le 8000 de Coolify
# n'en fait PAS partie : on y accède par un tunnel SSH, sinon l'interface
# d'administration de toute l'infrastructure serait exposée.
if ! command -v ufw >/dev/null 2>&1; then
  apt-get install -y -qq ufw >/dev/null
fi
ufw --force reset >/dev/null 2>&1 || true
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 22/tcp  >/dev/null   # ssh
ufw allow 80/tcp  >/dev/null   # http, et le défi Let's Encrypt
ufw allow 443/tcp >/dev/null   # https
ufw --force enable >/dev/null
dire "pare-feu : 22, 80, 443 ouverts, le reste fermé"

# ---------- Clé de la Storage Box ----------
# Sans elle, la sauvegarde nocturne échouera en silence le jour où le
# cron sera posé. On vérifie sa présence, on ne l'invente pas.
if [ -f /root/.ssh/storagebox ]; then
  chmod 600 /root/.ssh/storagebox
  dire "clé de la Storage Box présente"
else
  dire "ATTENTION : /root/.ssh/storagebox absente."
  dire "  À recopier depuis l'ancien serveur avant de poser le cron."
fi

# ---------- Contrôle final ----------
dire "=== État ==="
free -h | sed 's/^/  /'
df -h / | tail -1 | awk '{printf "  disque : %s utilisés sur %s (%s)\n", $3, $2, $5}'
dire "  latence vers la Storage Box :"
ping -c 3 -q u649821.your-storagebox.de 2>/dev/null | tail -1 | sed 's/^/    /' \
  || dire "    (injoignable - sans gravité à ce stade)"
dire "=== Prêt pour l'installation de Coolify ==="
