# Sauvegardes du VPS

Le VPS Hetzner héberge **les deux instances Supabase** (`api.amstc.org` et
`api.consultations-amstc.org`). Sans sauvegarde hors du serveur, une panne
matérielle ou une erreur de manipulation fait perdre définitivement les
comptes membres, les paiements, les cartes, les photos et toutes les
consultations. C'est le seul risque vraiment irréversible du système.

Le script `supabase/sauvegarde-vps.sh` traite les deux instances d'un coup :

- **Bases de données** : `pg_dumpall` complet (rôles compris), compressé.
- **Fichiers** : photos des membres et pièces jointes du Storage.
- **Copie hors du serveur** : envoi vers un espace distant (voir plus bas).
- **Rotation** : les sauvegardes de plus de 14 jours sont effacées.

Les conteneurs sont découverts automatiquement (`supabase-db-*` et
`supabase-storage-*`) : aucun identifiant n'est écrit en dur, la sauvegarde
continue donc de fonctionner si Coolify recrée un service.

---

## 1. Installer le script

Sur le VPS, connecté en SSH :

```bash
curl -fsSL https://raw.githubusercontent.com/mbadji1996-cell/site-amstc/main/supabase/sauvegarde-vps.sh -o /root/sauvegarde-amstc.sh && chmod +x /root/sauvegarde-amstc.sh && wc -l /root/sauvegarde-amstc.sh
```

Le compte doit afficher environ 160 lignes.

## 2. Vérifier à blanc (aucun fichier écrit)

**À faire avant tout le reste.** Cette commande ne sauvegarde rien : elle
vérifie seulement que les conteneurs sont trouvés et que leurs bases sont
lisibles.

```bash
bash /root/sauvegarde-amstc.sh --test
```

Vous devez voir **deux** lignes `supabase-db-...` avec une taille de base,
**deux** lignes `supabase-storage-...` avec un nombre de fichiers, et
l'espace disque disponible. Si une ligne affiche `ECHEC`, ne passez pas à
la suite : envoyez-moi la sortie.

## 3. Choisir la destination hors serveur

Une sauvegarde qui reste sur le VPS ne protège de rien en cas de panne du
VPS. Le plus simple chez Hetzner est une **Storage Box BX11** (1 To,
environ 4 € par mois), commandée depuis la console Hetzner.

Une fois la Storage Box créée, autorisez le VPS à y écrire sans mot de
passe :

```bash
ssh-keygen -t ed25519 -f /root/.ssh/storagebox -N "" && cat /root/.ssh/storagebox.pub
```

Copiez la clé affichée, puis dans l'interface Hetzner de la Storage Box :
**Sous-comptes / SSH keys** → collez la clé publique.

Testez la connexion (remplacez `u123456` par votre identifiant) :

```bash
ssh -p 23 -i /root/.ssh/storagebox u123456@u123456.your-storagebox.de ls
```

## 4. Première sauvegarde réelle

```bash
AMSTC_BACKUP_REMOTE="u123456@u123456.your-storagebox.de:amstc/" bash /root/sauvegarde-amstc.sh
```

Le script doit se terminer par `=== Sauvegarde terminée sans erreur ===`.
Vérifiez ensuite ce qui a été produit :

```bash
ls -lh /var/backups/amstc/
```

Vous devez avoir **quatre** fichiers : deux `_base.sql.gz` et deux
`_fichiers.tar.gz`.

## 5. Automatiser (tous les jours à 3 h du matin)

```bash
(crontab -l 2>/dev/null; echo '0 3 * * * AMSTC_BACKUP_REMOTE="u123456@u123456.your-storagebox.de:amstc/" /bin/bash /root/sauvegarde-amstc.sh') | crontab - && crontab -l
```

Si vous n'avez pas encore de Storage Box, installez quand même la tâche
sans la variable `AMSTC_BACKUP_REMOTE` : vous aurez au moins une
sauvegarde locale, qui protège des erreurs de manipulation (mais pas
d'une panne du serveur).

## 6. Tester une restauration - indispensable

Une sauvegarde jamais restaurée n'est pas une sauvegarde. À faire **une
fois**, sur une base jetable, jamais sur la base de production :

```bash
zcat /var/backups/amstc/*_rffqs8ck1ckdixkuu2xjo5sc_base.sql.gz | head -40
```

Vous devez voir des instructions `CREATE ROLE` puis `CREATE DATABASE`. Pour
aller plus loin, créez un conteneur Postgres temporaire et rejouez-y le
dump ; dites-le-moi et je vous donnerai la suite des commandes.

## Surveillance

Chaque exécution écrit dans `/var/backups/amstc/sauvegarde.log`. Pour voir
les dernières :

```bash
tail -30 /var/backups/amstc/sauvegarde.log
```

Le script s'arrête avec un code d'erreur si un dump est incomplet, et
supprime le fichier tronqué plutôt que de le garder : une sauvegarde
corrompue qui paraît valable est pire que pas de sauvegarde du tout.
