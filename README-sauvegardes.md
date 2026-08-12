# Sauvegardes du VPS

Le VPS Hetzner n'héberge pas que l'AMSTC. On y trouve **quatre bases de
données** :

| Conteneur | Ce qu'il contient |
|---|---|
| `supabase-db-rffqs8ck…` | Espace membres : comptes, cartes, paiements, cotisations |
| `supabase-db-qmy744bq…` | Consultations : données de patients |
| `db-sil739opnq…` | `sontencare.com` (base `plateforme_sanitaire`) |
| `coolify-db` | Configuration de Coolify, **et les variables d'environnement de tous les services** |

Ce dernier point est facile à sous-estimer : les variables d'environnement
ne vivent que dans la base de Coolify, jamais dans les fichiers `.env` du
disque. La perdre, c'est devoir reconfigurer chaque service à la main.

Sans sauvegarde hors du serveur, une panne matérielle ou une erreur de
manipulation fait perdre définitivement tout cela. C'est le seul risque
vraiment irréversible du système.

Le script `supabase/sauvegarde-vps.sh` traite le tout d'un coup :

- **Bases de données** : `pg_dumpall` complet (rôles compris), compressé.
- **Fichiers** : photos des membres et pièces jointes du Storage
  (~12 000 fichiers, sur le disque du conteneur `supabase-storage-*` -
  MinIO est présent mais inutilisé).
- **Copie hors du serveur** : envoi vers un espace distant (voir plus bas).
- **Rotation** : les sauvegardes de plus de 14 jours sont effacées.

Les conteneurs sont découverts automatiquement (`supabase-db-*`, `db-*`,
`coolify-db`, `supabase-storage-*`) : aucun identifiant n'est écrit en
dur. La sauvegarde continue donc de fonctionner si Coolify recrée un
service, et **une nouvelle application déployée est prise en compte sans
rien modifier**.

---

## 1. Installer le script

Sur le VPS, connecté en SSH :

```bash
curl -fsSL https://raw.githubusercontent.com/mbadji1996-cell/site-amstc/main/supabase/sauvegarde-vps.sh -o /root/sauvegarde-amstc.sh && chmod +x /root/sauvegarde-amstc.sh && wc -l /root/sauvegarde-amstc.sh
```

Le compte doit afficher **215** lignes.

## 2. Vérifier à blanc (aucun fichier écrit)

**À faire avant tout le reste.** Cette commande ne sauvegarde rien : elle
vérifie seulement que les conteneurs sont trouvés et que leurs bases sont
lisibles.

```bash
bash /root/sauvegarde-amstc.sh --test
```

Vous devez voir **quatre** lignes de bases (deux `supabase-db-…`, une `db-…`
et `coolify-db`), **deux** lignes `supabase-storage-…` avec un nombre de fichiers, et
l'espace disque disponible. Si une ligne affiche `ECHEC`, ne passez pas à
la suite : envoyez-moi la sortie.

## 3. Choisir la destination hors serveur

Une sauvegarde qui reste sur le VPS ne protège de rien en cas de panne du
VPS. Le plus simple chez Hetzner est une **Storage Box BX11** (1 To,
environ 4 € par mois), commandée depuis la console Hetzner.

Sur la page de la Storage Box : **Actions** → **Change settings** →
activez **SSH Support**. Laissez SMB et WebDAV desactives, on n'en a pas
besoin. Puis **Actions** → **Reset password** pour lui donner un mot de
passe : il ne servira qu'une fois, a la commande `install-ssh-key`.

Autorisez ensuite le VPS a y ecrire sans mot de passe :

```bash
ssh-keygen -t ed25519 -f /root/.ssh/storagebox -N "" && echo "cle creee"
```

```bash
cat /root/.ssh/storagebox.pub | ssh -p 23 u123456@u123456.your-storagebox.de install-ssh-key
```

`install-ssh-key` est une commande fournie par Hetzner sur les Storage
Box : elle evite d'aller coller la cle a la main dans l'interface.

Testez la connexion (remplacez `u123456` par votre identifiant) :

```bash
ssh -p 23 -i /root/.ssh/storagebox -o BatchMode=yes u123456@u123456.your-storagebox.de ls
```

`BatchMode=yes` interdit toute invite : si la cle n'etait pas correctement
installee, la commande echouerait franchement au lieu de reclamer un mot
de passe et de laisser croire que tout va bien.

La cle est attendue en `/root/.ssh/storagebox`. Le script la NOMME
explicitement lors de la copie : elle ne porte pas un des noms que ssh
essaie d'office, et sans cela la copie echouerait chaque nuit en
reclamant un mot de passe que personne n'est la pour saisir. Pour la
placer ailleurs, renseignez `AMSTC_BACKUP_KEY`.

## 4. Première sauvegarde réelle

```bash
AMSTC_BACKUP_REMOTE="u123456@u123456.your-storagebox.de:amstc/" bash /root/sauvegarde-amstc.sh
```

Le script doit se terminer par `=== Sauvegarde terminée sans erreur ===`.
Vérifiez ensuite ce qui a été produit :

```bash
ls -lh /var/backups/amstc/
```

Vous devez avoir **six** fichiers : quatre `_base.sql.gz` et deux
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
zcat /var/backups/amstc/*_supabase-rffqs8ck1ckdixkuu2xjo5sc_base.sql.gz | head -40
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

---

# Supervision (être prévenu quand quelque chose tombe)

Aujourd'hui, si le VPS ou une des deux API s'arrête, personne n'est
prévenu : on le découvre parce qu'un membre le signale. Pendant le Gamou,
c'est trop tard.

## Ce qu'il faut surveiller

| Adresse à surveiller | Ce que ça prouve |
|---|---|
| `https://amstc.org/` | Le site public est servi |
| `https://consultations-amstc.org/` | Le site consultations est servi |
| `https://api.amstc.org/functions/v1/sante?apikey=CLE_ANON_AMSTC` | VPS + proxy + **base amstc** |
| `https://api.consultations-amstc.org/functions/v1/sante?apikey=CLE_ANON_CONSULT` | VPS + proxy + **base consultations** |

Les clés `anon` sont publiques par conception (elles figurent déjà dans le
code du site) : les mettre dans une adresse de supervision ne présente
aucun risque. La sonde ne renvoie aucune donnée personnelle, seulement un
état et un compteur.

À défaut de déployer la fonction, `…/auth/v1/health?apikey=…` répond
également 200, mais ne prouve que le proxy : une base arrêtée passerait
inaperçue.

## 1. Déployer la sonde `sante` sur les deux instances

Sur le VPS, pour l'instance **amstc** :

```bash
curl -fsSL https://raw.githubusercontent.com/mbadji1996-cell/site-amstc/main/supabase/functions/sante/index.ts -o /tmp/sante.ts && docker exec supabase-edge-functions-rffqs8ck1ckdixkuu2xjo5sc mkdir -p /home/deno/functions/sante && docker cp /tmp/sante.ts supabase-edge-functions-rffqs8ck1ckdixkuu2xjo5sc:/home/deno/functions/sante/index.ts && docker restart supabase-edge-functions-rffqs8ck1ckdixkuu2xjo5sc
```

Puis pour l'instance **consultations** (même fichier, aucune adaptation) :

```bash
docker exec supabase-edge-functions-qmy744bqv0xnafmr9nndu34t mkdir -p /home/deno/functions/sante && docker cp /tmp/sante.ts supabase-edge-functions-qmy744bqv0xnafmr9nndu34t:/home/deno/functions/sante/index.ts && docker restart supabase-edge-functions-qmy744bqv0xnafmr9nndu34t
```

Vérifiez (remplacez la clé par la clé `anon` correspondante) :

```bash
curl -s "https://api.amstc.org/functions/v1/sante?apikey=CLE_ANON_AMSTC"
```

Vous devez recevoir `{"etat":"ok","base":"joignable","comptes":…}`. Si vous
recevez `"etat":"degrade"`, la base ne répond pas : c'est précisément ce
que la supervision doit détecter.

## 2. Créer les alertes

Sur [uptimerobot.com](https://uptimerobot.com) (offre gratuite : 50
surveillances, vérification toutes les 5 minutes) :

1. Créez un compte avec l'adresse qui doit recevoir les alertes.
2. **Add New Monitor** → type **HTTP(s)** → collez une des quatre adresses
   du tableau ci-dessus → intervalle **5 minutes**.
3. Répétez pour les quatre.
4. Dans **My Settings**, ajoutez un second contact d'alerte (une deuxième
   adresse e-mail, ou l'intégration WhatsApp/Telegram) : si la panne
   touche l'envoi d'e-mails, une seule adresse ne suffit pas.

Pour les deux adresses `sante`, réglez le monitor pour n'accepter **que
le code 200** : le 503 renvoyé par la sonde quand la base est en panne
doit déclencher l'alerte.

## 3. Vérifier que l'alerte fonctionne

Ne vous fiez pas à une supervision jamais déclenchée. Une fois installée,
mettez volontairement en pause l'un des services depuis Coolify pendant
deux minutes et vérifiez que l'alerte arrive bien. Remettez-le ensuite en
marche - à faire en dehors des heures d'affluence, et surtout pas pendant
le Gamou.
