# -*- coding: utf-8 -*-
u"""Ramene les televersements du CMS a une taille servable.

POURQUOI. Decap enregistre ce qu'on lui donne, sans y toucher. Une photo
sortie d'un appareil arrive donc en 6240 x 4160 et pese huit megaoctets,
pour etre affichee dans une colonne de 500 pixels. Une fiche d'actualite
mesuree avant ce script : 8,55 Mo pour une page, dont 7,9 pour la seule
image de couverture.

CE QUE FAIT LE SCRIPT.
  - Il ne regarde QUE les images citees quelque part dans le depot. Un
    televersement orphelin n'est jamais telecharge par un visiteur : le
    reduire ne gagnerait rien et effacerait peut-etre une piece qu'une
    page servie depuis Supabase reclame encore.
  - Il plafonne le cote le plus long a 1800 pixels. Au-dela, le site
    n'affiche jamais rien : le fond de hero fait 1920 de large sur un
    ecran ordinaire, la couverture d'article 1400 sur un ecran 2x, une
    vignette de liste 800.
  - Un JPEG reste un JPEG, sous le meme nom : aucune reference a
    reecrire.
  - Un PNG sans transparence est une photo rangee dans le mauvais
    format - il devient un JPEG, et TOUTES ses references sont
    reecrites dans le depot. Un PNG avec transparence reste un PNG.
  - L'original part dans un dossier hors du depot avant toute
    modification.

QUAND LE RELANCER. Apres une serie de televersements depuis le CMS :

    python scripts/alleger-televersements.py --simuler   (pour voir)
    python scripts/alleger-televersements.py             (pour agir)

Le mode « --simuler » n'ecrit rien et affiche le gain attendu.
"""
import io
import os
import shutil
import sys
from datetime import datetime

from PIL import Image

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPLOADS = os.path.join(RACINE, u'assets', u'uploads')
SAUVEGARDE = os.path.join(os.path.dirname(RACINE), u'uploads-originaux')

COTE_MAX = 1800
QUALITE = 82
SEUIL = 400 * 1024          # en dessous, on laisse tranquille
EXTENSIONS = (u'.jpg', u'.jpeg', u'.png')

# Les fichiers lus pour savoir qui est cite, et reecrits quand un PNG
# devient un JPEG.
SOURCES = (u'.html', u'.json', u'.md', u'.js', u'.css', u'.yml', u'.xml')
HORS = (u'/.git', u'/assets/uploads', u'/node_modules', u'/assets/vendor')


def fichiers_sources():
    for dossier, sous, fichiers in os.walk(RACINE):
        chemin = dossier.replace(os.sep, u'/')
        if any(x in chemin for x in HORS):
            sous[:] = []
            continue
        for f in fichiers:
            if f.endswith(SOURCES):
                yield os.path.join(dossier, f)


def a_de_la_transparence(im):
    u"""Un canal alpha ne suffit pas : encore faut-il qu'il serve."""
    if im.mode not in (u'RGBA', u'LA', u'PA'):
        return u'transparency' in im.info
    alpha = im.getchannel(u'A')
    return alpha.getextrema()[0] < 255


def humain(octets):
    return u'%.2f Mo' % (octets / 1048576.0)


def main():
    simuler = u'--simuler' in sys.argv

    corpus = {}
    for chemin in fichiers_sources():
        try:
            corpus[chemin] = io.open(chemin, encoding='utf-8', errors='replace').read()
        except Exception:
            pass
    tout = u'\n'.join(corpus.values())

    candidats = []
    for dossier, _, fichiers in os.walk(UPLOADS):
        for f in fichiers:
            if not f.lower().endswith(EXTENSIONS):
                continue
            p = os.path.join(dossier, f)
            if f not in tout:                      # orphelin : on n'y touche pas
                continue
            if os.path.getsize(p) < SEUIL:
                try:
                    with Image.open(p) as im:
                        if max(im.size) <= COTE_MAX:
                            continue
                except Exception:
                    continue
            candidats.append(p)

    if not candidats:
        print(u'rien a alleger')
        return

    if not simuler and not os.path.isdir(SAUVEGARDE):
        os.makedirs(SAUVEGARDE)

    avant_total = apres_total = 0
    renommages = {}      # ancien nom de fichier -> nouveau, pour les PNG devenus JPEG
    echecs = []

    for p in sorted(candidats):
        nom = os.path.basename(p)
        avant = os.path.getsize(p)
        try:
            im = Image.open(p)
            im.load()
        except Exception as e:
            echecs.append((nom, str(e)))
            continue

        larg, haut = im.size
        garde_png = p.lower().endswith(u'.png') and a_de_la_transparence(im)

        if max(larg, haut) > COTE_MAX:
            ratio = COTE_MAX / float(max(larg, haut))
            cible = (max(1, int(round(larg * ratio))), max(1, int(round(haut * ratio))))
            im = im.resize(cible, Image.LANCZOS)
        else:
            cible = (larg, haut)

        if garde_png:
            destination = p
            options = dict(format='PNG', optimize=True)
            if im.mode not in (u'RGBA', u'P', u'LA'):
                im = im.convert(u'RGBA')
        else:
            # On ne renomme QUE les PNG. Un « .jpeg » reste un « .jpeg » :
            # le transformer en « .jpg » ferait reecrire des references
            # sans rien gagner.
            if p.lower().endswith(u'.png'):
                destination = os.path.splitext(p)[0] + u'.jpg'
            else:
                destination = p
            options = dict(format='JPEG', quality=QUALITE, optimize=True, progressive=True)
            if im.mode != u'RGB':
                # Un alpha inutilise s'aplatit sur du blanc, pas sur du noir.
                if im.mode in (u'RGBA', u'LA', u'PA') or u'transparency' in im.info:
                    fond = Image.new(u'RGB', im.size, (255, 255, 255))
                    rgba = im.convert(u'RGBA')
                    fond.paste(rgba, mask=rgba.getchannel(u'A'))
                    im = fond
                else:
                    im = im.convert(u'RGB')

        tampon = io.BytesIO()
        im.save(tampon, **options)
        apres = tampon.tell()

        # Une image deja bien compressee peut ressortir plus lourde :
        # on ne remplace alors que si l'on a vraiment reduit.
        change_de_nom = destination != p
        if apres >= avant and not change_de_nom:
            im.close()
            continue

        avant_total += avant
        apres_total += apres
        fleche = u'%dx%d -> %dx%d' % (larg, haut, cible[0], cible[1])
        print(u'  %-46s %9s -> %9s   %s%s'
              % (nom[:46], humain(avant), humain(apres), fleche,
                 u'  (PNG -> JPEG)' if change_de_nom else u''))

        if not simuler:
            shutil.copy2(p, os.path.join(SAUVEGARDE, nom))
            with io.open(destination, 'wb') as sortie:
                sortie.write(tampon.getvalue())
            if change_de_nom:
                os.remove(p)
                renommages[nom] = os.path.basename(destination)
        im.close()

    # ---- Reecriture des references des PNG devenus JPEG ----
    touches = 0
    if renommages and not simuler:
        for chemin, contenu in corpus.items():
            neuf = contenu
            for ancien, nouveau in renommages.items():
                neuf = neuf.replace(ancien, nouveau)
            if neuf != contenu:
                io.open(chemin, 'w', encoding='utf-8', newline='\n').write(neuf)
                touches += 1

    print(u'')
    print(u'%d images : %s -> %s  (%.0f %% de moins)'
          % (len(candidats), humain(avant_total), humain(apres_total),
             100.0 * (avant_total - apres_total) / avant_total if avant_total else 0))
    if renommages:
        print(u'%d PNG devenus JPEG, %d fichiers du depot reecrits'
              % (len(renommages), touches))
    if echecs:
        print(u'illisibles : %s' % u', '.join(n for n, _ in echecs))
    if simuler:
        print(u'')
        print(u'SIMULATION : rien n a ete ecrit.')
    else:
        print(u'originaux conserves dans %s' % SAUVEGARDE)
        print(u'le %s' % datetime.now().strftime(u'%d/%m/%Y a %H:%M'))


if __name__ == '__main__':
    main()
