# Migration du VPS vers un CPX12

Du **CPX32 à Falkenstein** vers un **CPX12 à Helsinki** : 1 vCPU, 2 Go,
40 Go, **9,99 €/mois** IPv4 comprise.

Attention, les prix de la grille publique sont ceux d'Helsinki ;
Falkenstein porte un supplément de 2 à 3 €. Vérifiez la ligne de votre
facture actuelle pour connaître l'économie exacte - elle tourne autour
de **20 € par mois, 240 € par an**.

**Sontencare ne migre pas.** Le projet n'avance plus, et ses 201 Mo
sont précisément ce qui permet au CPX12 de tenir. Ses données restent
dans les sauvegardes, redéployables le jour où il repart.

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

Dans la console Hetzner, **Create a server** :

| Réglage | Valeur | Pourquoi |
|---|---|---|
| Location | **Helsinki (hel1)** | la moins chère des localisations, et surtout **celle de votre Storage Box** : mesurée à 33,6 ms de Falkenstein quand les deux datacenters allemands sont à 1,6 et 3,6 ms. La sauvegarde nocturne cesse de traverser l'Europe |
| Image | **Ubuntu 26.04 LTS** | celle du serveur actuel. Une migration n'est pas le moment de changer deux variables à la fois : Coolify 4.7.5 est déjà éprouvé dessus chez vous |
| Type | Shared · **Regular Performance** · **CPX12** | 1 vCPU, 2 Go, 40 Go. 9,49 € + 0,50 € d'IPv4 = **9,99 €/mois** |
| SSH key | `amstc-vps-admin` | empreinte `SHA256:mGAvjIgzr8qurSX+afSbSCJ1SWNJvF9VNS7t2IpoWOg` - c'est la clé qui ouvre déjà l'ancien serveur |
| Volumes, Firewall, Placement group | aucun | le pare-feu se fait en `ufw` à l'étape 4 |
| Backups (+20 %) | **non** | vous avez déjà vos sauvegardes, locales et sur Storage Box |
| IPv6 | laisser activé | gratuit, et l'actuel en a un |
| Name | `ajamat-cpx12` | l'actuel s'appelle `ajamat` |

Notez l'adresse IP affichée après la création. Dans la suite, `NOUVEAU`
la désigne.

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

### Trois pièges, et ils coûtent cher

**1. `APP_KEY` doit précéder la restauration.** Coolify chiffre les
variables d'environnement avec cette clé. Une base restaurée sous une
autre clé rend vos 248 secrets indéchiffrables - jetons Meta, clés
Supabase, mots de passe Postgres. Alignez-la, ainsi qu'`APP_ID`, AVANT
de restaurer :

```bash
# depuis votre poste
ssh root@ANCIEN 'grep -E "^(APP_KEY|APP_ID)=" /data/coolify/source/.env' > /tmp/cles.env
scp /tmp/cles.env root@NOUVEAU:/tmp/
ssh root@NOUVEAU 'f=/data/coolify/source/.env; cp $f $f.avant;   grep -vE "^(APP_KEY|APP_ID)=" $f > /tmp/n && cat /tmp/cles.env >> /tmp/n && mv /tmp/n $f'
```

Ne touchez PAS à `DB_PASSWORD` ni `REDIS_PASSWORD` : ils appartiennent
aux conteneurs neufs.

**2. Un `docker restart` ne relit pas le `.env`.** Le conteneur garde
l'environnement qu'il avait à sa création. Il faut le **recréer** :

```bash
cd /data/coolify/source
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate coolify
docker exec coolify printenv APP_KEY | sha256sum | cut -c1-12   # doit valoir celle de l'ancien
```

**3. `pg_dumpall` réinitialise le mot de passe du rôle.** Le dump
contient un `ALTER ROLE coolify ... PASSWORD` : après restauration, la
base attend le mot de passe de l'ANCIEN serveur, tandis que le `.env`
porte celui du nouveau. Remettez le rôle en accord avec le `.env` :

```bash
ssh root@NOUVEAU 'PW=$(grep ^DB_PASSWORD= /data/coolify/source/.env | cut -d= -f2-);   printf "ALTER ROLE coolify WITH PASSWORD %s%s%s;
" "'" "$PW" "'"   | docker exec -i coolify-db psql -U coolify -d postgres'
```

### La restauration

```bash
docker stop coolify coolify-realtime 2>/dev/null
docker exec coolify-db psql -U coolify -d postgres -c 'DROP DATABASE IF EXISTS coolify'
gunzip -c /tmp/coolify.sql.gz | docker exec -i coolify-db psql -U coolify -d postgres
```

Une seule erreur est attendue : `role "coolify" already exists`.

### Le contrôle qui dit si tout a pris

```bash
docker exec coolify php artisan tinker --execute '
  $ok=0; $ko=0;
  foreach (\App\Models\EnvironmentVariable::limit(400)->get() as $v) {
    try { $v->value; $ok++; } catch (\Throwable $e) { $ko++; }
  }
  echo "dechiffrees $ok, en echec $ko
";'
```

**`en echec 0` ou rien ne marchera.** Si le compte est non nul, c'est
que l'un des trois pièges ci-dessus n'a pas été désamorcé.

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

---

# Journal : migration du 19 novembre 2026

Le nouveau serveur **existe, tourne et porte vos données**. Rien n'est
en production : le DNS pointe toujours sur l'ancien.

| | |
|---|---|
| Adresse | `2.29.182.131` |
| Localisation | `hel1-dc2`, Helsinki |
| Gabarit | CPX12 - 1 vCPU, 1 909 Mo, 38 Go |
| Storage Box | **0,77 ms** (33,8 ms depuis Falkenstein) |
| Conteneurs | 20, aucun en mauvais état |
| Mémoire | **985 Mo de conteneurs**, 1 111 Mo utilisés sur 1 909 |
| Disque | 17 Go sur 38 (46 %) |

## Ce qui tient le budget mémoire

L'estimation était de 1 395 Mo. Le relevé donne 985. Deux réglages
expliquent l'écart :

| | ancien (4 vCPU) | nouveau (1 vCPU) |
|---|---|---|
| Kong ×2 | 530 Mo | **186 Mo** - un worker nginx par cœur, donc un seul |
| Postgres ×2 | 613 Mo | **155 Mo** - `shared_buffers` 128 → 32 Mo, `max_connections` 100 → 50 |

Le réglage Postgres n'est pas une contorsion : la base de l'espace
membres pèse 34 Mo, celle des consultations 18. Trente-deux mégaoctets
de cache les tiennent presque entières, et les cent connexions
réservaient de la mémoire pour des clients qui ne viennent jamais.

## Données vérifiées table par table

| | tables | contenu |
|---|---|---|
| Espace membres | **77 identiques** | 315 profils, 94 messages WhatsApp, 13 237 fichiers, 13 fonctions Edge |
| Consultations | **38 identiques** | 881 consultations, 318 profils, 6 sites, 104 médicaments |

Les six points de contrôle rendent les mêmes codes que l'ancien
serveur, testés avec `curl --resolve` comme si le DNS avait déjà
basculé : 400, 200, 400, 200, 403, 401.

## Deux pièges de plus, en sus des trois déjà documentés

**4. Les réseaux Docker n'existent pas sur la machine neuve.** Coolify
en crée un par service, et le fichier de composition les déclare
`external`. Sans eux, `docker compose up` télécharge les images puis ne
démarre rien, en disant seulement `network ... could not be found` :

```bash
for n in rffqs8ck1ckdixkuu2xjo5sc qmy744bqv0xnafmr9nndu34t; do
  docker network create --driver bridge --attachable "$n"
  docker network connect "$n" coolify-proxy
done
```

Le raccordement du proxy est aussi indispensable que la création : sans
lui Traefik ne voit pas les conteneurs et ne route rien.

**5. `pg_dumpall` restaure dans l'ordre alphabétique**, donc
`auth.identities` **avant** `auth.users`. La clé étrangère, déjà créée
par l'amorçage du conteneur neuf, refuse l'insertion. Résultat : une
base qui paraît complète, 315 comptes bien présents - et **personne ne
peut se connecter**, les 333 lignes qui relient un compte à son mode
d'authentification manquant à l'appel.

Même chose pour `sessions`, `refresh_tokens`, `mfa_amr_claims` et
`one_time_tokens`. Une fois `auth.users` peuplée, il suffit de rejouer
les blocs `COPY` concernés, dans cet ordre.

**Le contrôle qui l'aurait vu** - à faire sur les deux serveurs et à
comparer :

```sql
select table_schema||'.'||table_name||' = '||
  (xpath('/row/c/text()', query_to_xml(
    'select count(*) as c from '||quote_ident(table_schema)||'.'||quote_ident(table_name),
    false, true, '')))[1]::text::int
from information_schema.tables
where table_schema in ('public','auth','storage') and table_type='BASE TABLE'
order by 1;
```

Un `diff` entre les deux sorties doit être vide. Compter les lignes des
seules tables métier ne l'aurait pas vu.

## Ce qui reste, dans l'ordre

1. **Essayer depuis un navigateur** par le fichier `hosts` (étape 10) :
   connexion à l'espace membres, une page qui lit la base, une photo du
   Storage, un envoi WhatsApp.
2. **Abaisser les TTL à 300** la veille de la bascule.
3. **Basculer le DNS** sur `2.29.182.131` - quatre enregistrements.
   Traefik demandera alors ses certificats ; comptez une à deux minutes
   avant que le HTTPS réponde.
4. **Poser le cron de sauvegarde**, et seulement à ce moment-là :

   ```bash
   ssh root@2.29.182.131 'crontab -l 2>/dev/null; echo "0 3 * * * AMSTC_BACKUP_REMOTE=\"u649821@u649821.your-storagebox.de:amstc/\" /bin/bash /root/sauvegarde-amstc.sh" | crontab -'
   ```

   > **Pas avant la bascule.** Les deux serveurs écriraient dans le même
   > dossier distant, sous les mêmes noms de fichiers, et la purge
   > distante trancherait entre des sauvegardes qu'elle croirait
   > redondantes. Le script et la clé sont déjà en place sur le nouveau
   > serveur, l'essai à blanc est passé : il ne manque que cette ligne.

5. **Retirer le cron de l'ancien serveur** le même jour.
6. **Remettre les TTL à 3600**, puis supprimer l'ancien serveur après
   une semaine sans incident.

## Ce qui ne migre pas

**Sontencare** (`plateforme-sanitaire`) reste sur l'ancien serveur. Sa
configuration est présente dans le Coolify du nouveau - restaurée avec
le reste - mais ni ses fichiers ni sa base n'ont été transférés, et il
n'a pas été déployé. Ses 201 Mo sont précisément ce qui permet au CPX12
de tenir. Ses données restent dans les sauvegardes, redéployables le
jour où le projet repart.
