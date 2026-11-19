# Migration du VPS vers un CPX22

Du **CPX32 (4 vCPU, 8 Go, 160 Go, 29,99 €)** vers le **CPX22 (2 vCPU,
4 Go, 80 Go, 16,49 €)**. Économie : 13,50 € par mois, 162 € par an.

Ce document est une suite de commandes à exécuter dans l'ordre. Chaque
étape dit ce qu'elle fait et comment vérifier qu'elle a réussi.

---

## Pourquoi le CPX22 tient, maintenant

Avant le dégraissage du 19 novembre 2026, la machine portait 36
conteneurs pour 3 482 Mo. Elle en porte 22 pour **2 368 Mo**, sans rien
perdre : les composants retirés ne servaient pas.

| Retiré | Mo | Pourquoi |
|---|---|---|
| MinIO ×2 | 246 | inutilisé - voir `README-sauvegardes.md` |
| logflare / analytics ×2 | 336 | journaux jamais consultés |
| Studio ×2 | 293 | se rallume à la demande, voir plus bas |
| Realtime ×2 | 99 | **zéro abonnement en 7 jours** sur les deux piles |
| Supavisor ×2 | 92 | rien ne passe par le pooler |
| vector ×2 | 28 | n'alimentait que logflare |
| imgproxy ×2 | 28 | aucune transformation d'image |
| backends Postgres libérés | ~930 | Realtime et Supavisor tenaient 14 connexions par base |

Les deux Postgres sont retombés de 969 à 414 Mo et de 574 à 199 Mo.

**Budget sur le CPX22** : 2 368 Mo de conteneurs + ~1 000 Mo d'hôte =
**3,4 Go sur 4**. Serré mais tenable, avec le fichier d'échange de
l'étape 4. Si la marge vous paraît trop mince après quelques semaines,
Hetzner permet de remonter au CPX32 **en gardant la taille du disque** :
l'opération est réversible et prend quelques minutes, machine éteinte.
L'inverse - agrandir le disque - est définitif. C'est pour cela qu'on
part petit.

### Rallumer Studio quand vous en avez besoin

```bash
docker start supabase-studio-rffqs8ck1ckdixkuu2xjo5sc   # espace membres
docker start supabase-studio-qmy744bqv0xnafmr9nndu34t   # consultations
```

et pour le réétendre après usage, `docker stop` sur les mêmes noms.
L'éditeur SQL n'est disponible que pendant ce temps-là.

---

## Ce qui doit voyager

| | Taille | Où c'est |
|---|---|---|
| Images Docker | 15,2 Go | se retéléchargent, rien à copier |
| `/data/coolify` | 2,2 Go | **à copier** : fichiers du Storage, 13 fonctions Edge, configurations |
| Bases de données | 58 Mo de dumps | **à restaurer**, pas à copier |
| `coolify-db` | 1,1 Mo | **la pièce maîtresse**, voir ci-dessous |

**Les variables d'environnement de tous les services ne vivent que dans
`coolify-db`.** Pas dans des fichiers `.env`, pas sur le disque. Clés
JWT, clés d'API Supabase, jeton Meta, jeton Telegram : tout est là. La
perdre, c'est reconfigurer chaque service à la main sans savoir ce qu'il
y avait avant.

Les bases se restaurent depuis les dumps plutôt qu'en copiant les
volumes : Postgres repart propre, et les **3,9 Go de WAL accumulés ne
font pas le voyage**. C'est ce qui ramène l'empreinte disque de 62 à
environ 24 Go - auxquels s'ajoutent 11 Go de sauvegardes locales, soit
35 Go sur les 80 du CPX22.

---

## 1. La veille - abaisser les TTL DNS

Vos enregistrements sont à 2 heures. Tant qu'ils y restent, la bascule
traînera deux heures. La veille au soir, chez votre registrar, passez à
**300 secondes** :

```
api.amstc.org                A   167.233.231.165   TTL 300
api.consultations-amstc.org  A   167.233.231.165   TTL 300
sontencare.com               A   167.233.231.165   TTL 300
www.sontencare.com           A   167.233.231.165   TTL 300
```

Ne changez pas encore l'adresse, seulement le TTL. Vérifiez le
lendemain :

```bash
dig +noall +answer api.amstc.org
```

Le TTL affiché doit être inférieur ou égal à 300.

---

## 2. Créer le serveur

Dans la console Hetzner : **CPX22**, même datacenter que l'actuel
(la latence vers la Storage Box compte pour les sauvegardes), image
**Ubuntu 24.04**, et **votre clé SSH existante** - celle qui ouvre déjà
l'ancien serveur.

Notez l'adresse IP du nouveau serveur. Dans la suite, `NOUVEAU` la
désigne.

```bash
ssh root@NOUVEAU 'hostnamectl; free -m | head -2; df -h / | tail -1'
```

---

## 3. Sauvegarde fraîche, et vérifiée

Sur **l'ancien** serveur, sans attendre le cron de 3 h :

```bash
AMSTC_BACKUP_REMOTE="u649821@u649821.your-storagebox.de:amstc/" \
  /bin/bash /root/sauvegarde-amstc.sh
```

Puis, et c'est non négociable :

```bash
tail -20 /var/backups/amstc/sauvegarde.log
```

Vous devez y lire `Envoi vers ... OK` puis `Sauvegarde terminée sans
erreur`. Si l'envoi distant a échoué, **arrêtez-vous là** : ne migrez
pas avec une seule copie des données.

---

## 4. Préparer le nouveau serveur

```bash
ssh root@NOUVEAU
apt update && apt upgrade -y
timedatectl set-timezone Africa/Dakar
```

Le fichier d'échange - 2 Go, pour que les pages froides aient où aller.
Sur 4 Go de mémoire ce n'est pas un luxe, c'est ce que fait déjà votre
serveur actuel sans que personne s'en aperçoive :

```bash
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
sysctl -w vm.swappiness=10 && echo 'vm.swappiness=10' >> /etc/sysctl.d/99-swap.conf
free -h
```

Le pare-feu - seuls 22, 80 et 443 sont nécessaires :

```bash
ufw default deny incoming && ufw default allow outgoing
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp
ufw --force enable && ufw status
```

---

## 5. Installer Coolify, **dans la même version**

Une version différente lit mal la base restaurée à l'étape suivante.
L'ancien serveur tourne en **4.7.5** (`docker ps --format '{{.Image}}' |
grep coolify` pour le confirmer le jour venu).

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

Ouvrez `http://NOUVEAU:8000`, créez le compte administrateur, puis
**arrêtez-vous** : ne déployez encore aucun service.

---

## 6. Restaurer la configuration Coolify

C'est l'étape qui rend tout le reste possible : elle rapatrie les
services, leurs UUID et **toutes les variables d'environnement**.

Depuis votre poste :

```bash
scp root@ANCIEN:/var/backups/amstc/*_coolify-config_base.sql.gz /tmp/
scp /tmp/*_coolify-config_base.sql.gz root@NOUVEAU:/tmp/coolify.sql.gz
```

Sur le nouveau serveur :

```bash
docker stop coolify coolify-realtime 2>/dev/null
gunzip -c /tmp/coolify.sql.gz | docker exec -i coolify-db psql -U coolify -d postgres
docker start coolify coolify-realtime
```

Rechargez l'interface : vos trois services doivent apparaître, à
l'arrêt. **Vérifiez qu'un service affiche bien ses variables
d'environnement** avant de continuer - c'est le test qui dit si la
restauration a pris.

---

## 7. Copier les fichiers des services

Les 13 fonctions Edge, les 13 230 fichiers du Storage et les
configurations. Les UUID des dossiers doivent être identiques, c'est
pourquoi l'étape 6 vient avant.

```bash
ssh root@ANCIEN 'systemctl stop docker' ; # fige l'écriture, 2 minutes d'interruption
rsync -avz --progress -e ssh root@ANCIEN:/data/coolify/ root@NOUVEAU:/data/coolify/
ssh root@ANCIEN 'systemctl start docker'
```

> Si vous préférez éviter toute interruption sur l'ancien serveur,
> lancez le `rsync` sans arrêter Docker, puis **relancez-le une seconde
> fois juste avant la bascule DNS** : il ne transférera que ce qui a
> changé entre-temps.

Vérifiez :

```bash
ssh root@NOUVEAU 'ls /data/coolify/services/rffqs8ck1ckdixkuu2xjo5sc/volumes/functions | wc -l'
```

Treize fonctions attendues.

---

## 8. Déployer les services, puis restaurer les bases

Dans l'interface Coolify, déployez les trois services **un par un**.
Chacun retélécharge ses images et démarre avec des bases vides - c'est
normal.

Puis, pour chaque base, depuis votre poste :

```bash
scp root@ANCIEN:/var/backups/amstc/*_supabase-rffqs8ck1ckdixkuu2xjo5sc_base.sql.gz /tmp/
scp /tmp/*_supabase-rffqs8ck1ckdixkuu2xjo5sc_base.sql.gz root@NOUVEAU:/tmp/amstc.sql.gz
ssh root@NOUVEAU 'gunzip -c /tmp/amstc.sql.gz | docker exec -i supabase-db-rffqs8ck1ckdixkuu2xjo5sc psql -U supabase_admin -d postgres'
```

Répétez pour `qmy744bqv0xnafmr9nndu34t` (consultations) et
`sil739opnqsqdj2rwg88d79d` (sontencare).

`pg_dumpall` restaure les rôles en même temps que les données ; des
messages « role already exists » sont attendus et sans conséquence.

Contrôle :

```bash
ssh root@NOUVEAU 'docker exec supabase-db-rffqs8ck1ckdixkuu2xjo5sc psql -U supabase_admin -d postgres -c "select count(*) from profiles"'
```

---

## 9. Appliquer le dégraissage dès le départ

Pour ne pas réimporter les 1 114 Mo que vous venez d'économiser :

```bash
ssh root@NOUVEAU 'docker stop \
  supabase-minio-rffqs8ck1ckdixkuu2xjo5sc supabase-minio-qmy744bqv0xnafmr9nndu34t \
  imgproxy-rffqs8ck1ckdixkuu2xjo5sc imgproxy-qmy744bqv0xnafmr9nndu34t \
  supabase-vector-rffqs8ck1ckdixkuu2xjo5sc supabase-vector-qmy744bqv0xnafmr9nndu34t \
  supabase-analytics-rffqs8ck1ckdixkuu2xjo5sc supabase-analytics-qmy744bqv0xnafmr9nndu34t \
  realtime-dev-rffqs8ck1ckdixkuu2xjo5sc realtime-dev-qmy744bqv0xnafmr9nndu34t \
  supabase-supavisor-rffqs8ck1ckdixkuu2xjo5sc supabase-supavisor-qmy744bqv0xnafmr9nndu34t \
  supabase-studio-rffqs8ck1ckdixkuu2xjo5sc supabase-studio-qmy744bqv0xnafmr9nndu34t'
ssh root@NOUVEAU 'free -m | head -2'
```

Attendu : environ 3,4 Go utilisés.

---

## 10. Essayer avant de basculer

Sans toucher au DNS, forcez votre poste à voir le nouveau serveur.
Ajoutez à `C:\Windows\System32\drivers\etc\hosts` (bloc-notes en
administrateur) :

```
NOUVEAU  api.amstc.org
NOUVEAU  api.consultations-amstc.org
NOUVEAU  sontencare.com
```

Puis parcourez l'espace membres : connexion, une page qui lit la base,
une photo du Storage, un envoi WhatsApp. **Retirez ces lignes ensuite**,
sans quoi vous serez seul à voir le nouveau serveur.

---

## 11. La bascule

Chez le registrar, remplacez l'adresse par celle du nouveau serveur sur
les quatre enregistrements. Avec un TTL à 300, la propagation prend
cinq à dix minutes.

Traefik demandera de nouveaux certificats dès que le DNS pointera chez
lui ; comptez une minute ou deux avant que le HTTPS réponde.

**Laissez l'ancien serveur allumé.** Il ne coûte que quelques centimes
par heure et c'est votre retour arrière.

Contrôle, depuis votre poste :

```bash
bash /tmp/sante.sh    # le script de contrôle utilisé pendant le dégraissage
```

Les huit codes doivent être identiques à ceux d'avant la migration :
400, 200, 400, 200, 403, 401, 200, 200.

---

## 12. Le lendemain

- **Le webhook Meta** : il pointe sur `api.amstc.org`, donc rien à
  changer. Vérifiez quand même qu'un message WhatsApp entrant arrive
  bien dans la boîte.
- **Le cron de sauvegarde** : il n'est pas migré par Coolify, il faut le
  réinstaller.

  ```bash
  ssh root@NOUVEAU 'curl -fsSL https://raw.githubusercontent.com/mbadji1996-cell/site-amstc/main/supabase/sauvegarde-vps.sh -o /root/sauvegarde-amstc.sh && chmod +x /root/sauvegarde-amstc.sh'
  ```

  Recopiez la clé de la Storage Box (`/root/.ssh/storagebox*`) et la
  ligne de crontab depuis l'ancien serveur.

  Le script gère désormais quatre rétentions, parce qu'il y a deux
  lieux et deux poids. L'envoi ne se fait plus avec `rsync --delete` :
  le distant n'est plus le reflet du local, il accumule, et une
  fonction de purge décide seule de ce qu'il garde - en lisant la date
  dans le nom des fichiers, la Storage Box n'offrant pas `find`.

  | | local | distant |
  |---|---|---|
  | archives de fichiers (2 Go/nuit) | 3 jours | 14 jours |
  | dumps de bases (58 Mo/nuit) | 14 jours | 60 jours |

  Résultat mesuré le 19 novembre : **11 Go en local au lieu de 29**,
  profondeur distante intacte, et l'historique des bases passé de 14 à
  60 jours. Avec 24 Go de données, cela fait **35 Go sur les 80 du
  CPX22, soit 44 %**.
- **Remettre les TTL à 3600** une fois tout confirmé.

Après une semaine sans incident, supprimez l'ancien serveur depuis la
console Hetzner. Pas avant.

---

## Si quelque chose tourne mal

Tant que le DNS n'est pas basculé, il ne se passe rien : l'ancien
serveur sert toujours. Après la bascule, le retour arrière consiste à
remettre l'ancienne adresse IP sur les quatre enregistrements - cinq
minutes avec un TTL à 300.

C'est la raison pour laquelle on abaisse les TTL la veille et on garde
l'ancienne machine une semaine : **la marche arrière doit rester plus
rapide que le diagnostic**.
