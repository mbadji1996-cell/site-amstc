# -*- coding: utf-8 -*-
u"""Telecharge les polices du site et fait pointer les pages dessus.

POURQUOI. Les caracteres venaient de Google Fonts : soixante-douze pages
demandaient leur feuille a fonts.googleapis.com, puis les fichiers a
fonts.gstatic.com. Trois raisons d'en finir.

  1. La panne. C'est le meme risque que celui qui a efface les icones du
     site : si Google repond mal, le texte tombe dans la police du
     systeme et la page change d'allure d'un coup.
  2. La lenteur. Deux connexions a un tiers avant la premiere lettre,
     sur un reseau mobile senegalais, se paient comptant.
  3. Le visiteur. Chaque page annoncait sa visite a Google, sans que
     personne l'ait demande.

CE QUE FAIT CE SCRIPT. Il lit la feuille de Google pour chaque famille -
en se declarant comme un navigateur moderne, sans quoi Google renvoie de
vieux formats - telecharge les fichiers woff2, et ecrit dans
assets/vendor/fonts/ une feuille locale equivalente. Puis il remplace,
dans toutes les pages, l'adresse de Google par cette feuille.

Les blocs @font-face gardent leur « unicode-range » : le navigateur ne
telecharge le latin etendu, ou l'arabe d'Amiri, que si la page en a
besoin. Une seule feuille pour tout le site ne coute donc rien de plus
qu'une feuille par page.

POUR AJOUTER une graisse ou une famille : la declarer ci-dessous et
relancer

    python scripts/heberger-polices.py
"""
import io
import os
import re
import sys
import urllib.request

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(RACINE, 'assets', 'vendor')
FONTS = os.path.join(VENDOR, 'fonts')
FEUILLE = os.path.join(VENDOR, 'fonts-amstc.css')

# Un navigateur recent, sinon Google sert du woff (deux fois plus lourd)
# voire du ttf.
UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36')

# Une PLAGE de graisses (400..800) plutot qu'une liste : Google sert
# alors la police VARIABLE - un seul fichier qui porte toutes les
# graisses, quand la liste en demandait un par graisse. Pour Inter,
# 188 Ko en quatre fichiers deviennent 48 Ko en un seul.
# Amiri n'existe qu'en version fixe : elle garde ses deux graisses.
FAMILLES = [
    ('Sora', '400..800'),
    ('Inter', '400..700'),
    ('JetBrains+Mono', '400..500'),
    ('Amiri', '400;700'),          # le texte arabe de la page d'accueil
]

# Les jeux de caracteres qu'on garde. Le site ecrit en francais ; Amiri
# sert a l'arabe. Le cyrillique, le grec et le vietnamien sont ecartes.
SOUS_ENSEMBLES = ('latin', 'latin-ext', 'arabic')

# Les adresses de Google rencontrees dans les pages : toutes remplacees
# par la feuille locale, qui couvre l'union des graisses demandees.
ADRESSES = [
    'https://fonts.googleapis.com/css2?family=Sora:wght@400;500;600;700;800&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&family=Amiri:wght@400;700&display=swap',
    'https://fonts.googleapis.com/css2?family=Sora:wght@400;500;600;700;800&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap',
    'https://fonts.googleapis.com/css2?family=Sora:wght@400;500;600;700;800&family=Inter:wght@400;500;600;700&display=swap',
    'https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700;800&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap',
    'https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700;800&family=Inter:wght@400;500;600&display=swap',
    'https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap',
    'https://fonts.googleapis.com/css2?family=Sora:wght@600;700;800&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap',
]

EXTENSIONS = ('.html', '.css', '.js')
IGNORER = ('/node_modules/', '/.git/', '/assets/vendor/')


def lire(url):
    r = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(r) as reponse:
        return reponse.read()


def fabriquer_feuille():
    if not os.path.isdir(FONTS):
        os.makedirs(FONTS)
    blocs = []
    fichiers = 0
    poids_total = 0

    for famille, graisses in FAMILLES:
        url = ('https://fonts.googleapis.com/css2?family=%s:wght@%s&display=swap'
               % (famille, graisses))
        css = lire(url).decode('utf-8')
        sous_ensemble = None
        for bloc in re.split(r'(?=/\* )', css):
            m = re.match(r'/\* ([a-z-]+) \*/', bloc)
            if m:
                sous_ensemble = m.group(1)
            if '@font-face' not in bloc:
                continue
            if sous_ensemble not in SOUS_ENSEMBLES:
                continue
            lien = re.search(r'url\((https://fonts\.gstatic\.com/[^)]+)\)', bloc)
            graisse = re.search(r'font-weight:\s*([\d ]+)', bloc)
            if not lien or not graisse:
                continue
            # « 400 800 » pour une police variable, « 700 » pour une fixe.
            etiquette = graisse.group(1).strip().replace(' ', '-')
            nom = '%s-%s-%s.woff2' % (famille.replace('+', '-').lower(),
                                      etiquette, sous_ensemble)
            chemin = os.path.join(FONTS, nom)
            if not os.path.exists(chemin):
                with open(chemin, 'wb') as f:
                    f.write(lire(lien.group(1)))
            fichiers += 1
            poids_total += os.path.getsize(chemin)
            blocs.append(bloc.replace(lien.group(1), 'fonts/' + nom).strip())

    entete = (u"/* Polices du site, servies par amstc.org et non plus par Google.\n"
              u"   Fichier ENGENDRE par scripts/heberger-polices.py : ne pas modifier\n"
              u"   a la main. Les blocs gardent leur unicode-range, donc le navigateur\n"
              u"   ne telecharge que les jeux de caracteres que la page emploie. */\n\n")
    io.open(FEUILLE, 'w', encoding='utf-8', newline='\n').write(entete + u'\n\n'.join(blocs) + u'\n')
    return fichiers, poids_total


def pages():
    for dossier, sous, fichiers in os.walk(RACINE):
        c = dossier.replace('\\', '/') + '/'
        if any(x in c for x in IGNORER):
            sous[:] = []
            continue
        for f in fichiers:
            if f.endswith(EXTENSIONS):
                yield os.path.join(dossier, f)


def brancher():
    touchees = 0
    for p in pages():
        s = io.open(p, encoding='utf-8').read()
        depart = s
        rel = os.path.relpath(p, RACINE).replace('\\', '/')
        prefixe = '../' * rel.count('/')
        local = prefixe + 'assets/vendor/fonts-amstc.css'
        for a in ADRESSES:
            s = s.replace(a, local)
        # Les preconnexions ne servaient qu'a Google.
        s = re.sub(r'[ \t]*<link rel="preconnect" href="https://fonts\.(googleapis|gstatic)\.com"[^>]*>\n?', '', s)
        if s != depart:
            io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
            touchees += 1
    return touchees


def restes():
    trouves = []
    for p in pages():
        s = io.open(p, encoding='utf-8').read()
        if 'fonts.googleapis.com' in s or 'fonts.gstatic.com' in s:
            trouves.append(os.path.relpath(p, RACINE))
    return trouves


def main():
    fichiers, poids = fabriquer_feuille()
    print(u'%d fichiers de police, %.0f Ko' % (fichiers, poids / 1024.0))
    print(u'assets/vendor/fonts-amstc.css ecrit')
    print(u'%d pages branchees sur la feuille locale' % brancher())
    reste = restes()
    if reste:
        print(u'\nAppels restants a Google Fonts :')
        for r in reste:
            print(u'  %s' % r)
    else:
        print(u'plus aucun appel a Google Fonts')
    return 0


if __name__ == '__main__':
    sys.exit(main())
