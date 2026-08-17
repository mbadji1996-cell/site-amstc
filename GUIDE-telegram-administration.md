# Le bot Telegram de l'AMSTC - guide de l'administration

Ce guide s'adresse aux membres du **groupe Telegram d'administration**. Le bot y fait trois choses : il **prévient** de tout ce qui arrive, il **exécute** vos décisions d'un clic, et il **répond** à vos questions sur l'état de l'association.

Rien de ce qu'il fait n'est réservé au site. Mais rien n'est perdu non plus : chaque décision prise depuis Telegram est inscrite au journal d'administration avec le nom de celui qui a cliqué.

---

## 1. Ce qui arrive dans le groupe

Chaque événement produit un message avec, dessous, les boutons qui vont avec.

| Événement | Boutons |
|---|---|
| Nouvelle inscription | ✅ Approuver · ✖️ Refuser · 🔎 Voir la fiche |
| Paiement de validité de carte déclaré | ✅ Confirmer · ✖️ Refuser · 🔎 Voir la fiche |
| Paiement de cotisation déclaré | ✅ Confirmer · ✖️ Refuser · 🔎 Voir la fiche |
| Justificatif envoyé au bot par un membre | ✅ Confirmer [sa déclaration] · 📁 Classer traité · ✖️ Écarter |
| Nouveauté publiée sur le site public | 📣 Publier sur la chaîne · ✖️ Ne pas publier |
| Commande boutique, réclamation de carte, demande de campagne, sujet de forum, participation à une collecte | 🔎 Voir la fiche |

Et deux messages sans événement :

- **Le point du jour, à 8 h** - tout ce qui attend, tous onglets confondus. Il ne vient **que s'il y a quelque chose** : le silence veut dire « rien à faire ».
- **Les dossiers oubliés, le lundi à 8 h 30** - ce qui attend depuis plus de 48 heures.

**Une inscription qui signale « doublon probable »** partage un téléphone ou un nom avec un compte existant. C'est souvent quelqu'un qui a créé un compte au lieu de réclamer sa carte, ou l'inverse. Vérifiez avant d'approuver.

---

## 2. Traiter une inscription - le parcours complet

1. **Approuver.** Le message se réécrit : « Inscription approuvée : [nom] », et un bouton **✉️ Prévenir le membre** apparaît.
2. **Prévenir le membre.** Un menu de six messages s'ouvre - les mêmes que ceux de l'écran Validation du site :

   | Choix | Quand |
   |---|---|
   | 📇 Carte expirée | sa carte n'est plus valide |
   | 🔄 Carte à renouveler bientôt | elle expire en fin d'année |
   | 💰 Cotisations en retard | mois impayés |
   | ✅ Compte activé - se connecter | **le premier message à envoyer après une approbation** |
   | 💳 Rappel de paiement | nouvel adhérent : montants et numéros Wave / Orange Money |
   | ✍️ Message libre | le bot demande votre texte - **répondez à son message** |

3. Choisissez. Un bouton vert **💬 Envoyer sur WhatsApp à [prénom]** apparaît : touchez-le, WhatsApp s'ouvre sur votre téléphone avec le message prêt, envoyez.

C'est **votre** WhatsApp qui envoie, pas le serveur - c'est voulu, un serveur ne peut pas envoyer de WhatsApp libre. Si le membre n'a pas de numéro, le bot lui écrit sur Telegram ou par e-mail à votre place, et le dit.

Pour un nouvel adhérent, envoyez ensuite **💳 Rappel de paiement**.

---

## 3. Traiter un paiement

**Déclaré sur le site** : la notification porte le montant, les mois ou années, la référence. Vérifiez la transaction, puis **✅ Confirmer**. La carte ou les cotisations du membre sont mises à jour aussitôt.

**Justificatif reçu par le bot** : l'image arrive avec la fiche du membre. Trois cas.

- Il a **déjà déclaré** son paiement sur le site : le bouton **✅ Confirmer : [sa déclaration]** est là. Un clic, c'est fait.
- Il **n'a rien déclaré** : la légende le dit (« ⚠ Aucune déclaration en attente »). Il faut qu'il déclare sur le site, ou que vous enregistriez à la main.
- La capture **ne correspond à rien** : **✖️ Écarter**.

Dans tous les cas, quand vous en avez fini avec l'image, **📁 Classer traité** - sinon elle reste comptée dans le point du jour. Confirmer le paiement ne classe pas le justificatif : ce sont deux gestes.

---

## 4. Poser une question au bot

Tapez la commande dans le groupe. Si le bot ne réagit pas, ajoutez son nom : `/point@amstc_notifs_bot`.

| Commande | Ce qu'elle donne |
|---|---|
| **/point** | ce qui attend, tous onglets confondus - **le sommaire** ; ses boutons mènent aux quatre suivantes |
| **/attente** | qui attend, nommément - un bouton par inscription pour ouvrir sa fiche |
| **/justificatifs** | les captures reçues et non classées, réaffichées avec leurs boutons |
| **/cotisations** | l'état de l'année : à jour, partiels, aucun mois, encaissé, les cinq plus en retard |
| **/cartes** | les cartes non attribuées - **deux listes**, voir ci-dessous |
| **/membre** *nom* | la fiche de quelqu'un, avec Prévenir et Voir la fiche dessous |
| **/diffusion** *texte* | une annonce à tous les membres rattachés - voir §5 |
| **/aide** | cette liste |

**/membre** cherche par nom, e-mail, téléphone ou numéro de carte. Deux caractères suffisent. Plusieurs résultats donnent une liste à toucher.

**/cartes** distingue deux choses qu'on confond : les cartes du **registre** que personne n'a réclamées (des gens qui n'ont jamais créé de compte - rien à faire d'ici, l'écran des cartes s'en occupe), et les **membres inscrits sans numéro** (le compte existe, la carte manque - un bouton par personne).

---

## 5. Parler à tous les membres

`/diffusion` suivi du texte, sur une ou plusieurs lignes :

```
/diffusion Assemblée générale samedi 10 h au siège. Présence indispensable.
```

**Rien ne part.** Le bot affiche le texte tel qu'il sera reçu, le nombre de destinataires, et deux boutons : **📣 Envoyer à N membre(s)** ou **✖️ Annuler**. Une annonce partie ne se rattrape pas ; relisez.

Une annonce déjà envoyée ne peut pas être renvoyée d'un reclic.

Ne touche que les membres qui ont **rattaché** leur Telegram. Pour les autres, l'écran Diffusion WhatsApp du site reste l'outil.

---

## 6. La chaîne publique

Quand un article, une formation, un projet ou un événement est publié sur le site, le bot le **propose** dans le groupe tel qu'il paraîtrait, avec **📣 Publier sur la chaîne** ou **✖️ Ne pas publier**. Rien ne part aux abonnés sans un clic. La proposition passe dans l'heure qui suit la publication.

---

## 7. Ce qui part tout seul

| Quand | Quoi | À qui |
|---|---|---|
| Tous les jours, 8 h | Le point du jour (s'il y a quelque chose) | le groupe |
| Le lundi, 8 h 30 | Les dossiers en attente depuis plus de 48 h | le groupe |
| Le 5 du mois, 9 h | Rappel de la cotisation du mois | chaque membre rattaché non à jour |
| Le 1er du mois, 9 h | Rappel d'échéance de carte (dès novembre, ou déjà expirée) | chaque membre rattaché concerné + un bilan au groupe |

Aucun membre ne reçoit deux fois le même rappel. Les membres **non rattachés** ne reçoivent rien : le bilan au groupe vous dit combien sont à relancer à la main - c'est ce à quoi sert le menu Prévenir.

---

## 8. Ce que le bot ne fait pas

- **Il ne décide pas.** Il approuve, confirme, refuse **parce que vous avez cliqué**. Une capture d'écran n'est pas une preuve vérifiée ; c'est vous qui regardez le montant.
- **Il n'envoie pas de WhatsApp.** Il prépare le lien, votre téléphone envoie.
- **Il ne répond pas aux membres dans le groupe** - seulement en conversation privée, et seulement sur leur propre dossier.
- **Il n'obéit qu'au groupe d'administration.** Un clic venant d'ailleurs est refusé.

---

## 9. En cas de doute

- **Un bouton ne répond pas, ou « Échec »** : la base n'a peut-être pas la dernière phase, ou la fonction n'est pas redéployée. Le script `supabase/verifier-fonctions.sh` sur le VPS le dit.
- **Le bot ignore `/membre`** : ajoutez `@amstc_notifs_bot` après la commande. Pour que ce ne soit plus nécessaire : chez @BotFather, `/setprivacy` › votre bot › **Disable**.
- **Un membre dit ne rien recevoir** : il n'a probablement pas rattaché son Telegram. `/membre` son nom : la fiche dit « Telegram : non rattaché ».

Tout ce que le bot fait se retrouve sur le site : rien n'oblige à passer par lui.

*©AMSTC - août 2026*
