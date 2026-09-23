# -*- coding: utf-8 -*-
u"""Fabrique la police d'icones du site, reduite aux icones utilisees.

POURQUOI. Les icones venaient d'un CDN (jsdelivr, @tabler/icons-webfont
en version « latest »). Trois ennuis : la page depend d'un serveur
tiers - quand il repond mal, toutes les icones disparaissent ; « latest »
peut changer de version du jour au lendemain, et une icone renommee
s'efface sans prevenir ; la police complete pese 780 Ko pour environ
cinq mille icones, alors que le site en utilise moins de deux cents.

CE QUE FAIT CE SCRIPT. Il releve tous les noms « ti-… » ecrits dans le
depot, telecharge la police officielle, n'en garde que les glyphes
correspondants et ecrit deux fichiers dans assets/vendor :
tabler-amstc.woff2 et tabler-amstc.css. Les pages chargent ce CSS.

QUAND LE RELANCER. Des qu'une nouvelle icone est utilisee dans une page,
un script ou une fiche :

    python scripts/construire-icones.py

Il signale au passage les noms qui n'existent pas dans la police - c'est
ainsi qu'on a vu que « ti-handshake » avait disparu de la version 2.47.
"""
import io
import os
import re
import sys
import urllib.request

VERSION = u'2.47.0'
CSS_CDN = u'https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@%s/tabler-icons.min.css' % VERSION
FONT_CDN = u'https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@%s/fonts/tabler-icons.woff2' % VERSION

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(RACINE, 'assets', 'vendor')
CACHE = os.path.join(VENDOR, '.cache')

EXTENSIONS = ('.html', '.js', '.json', '.css', '.md')
IGNORER = ('/node_modules/', '/.git/', '/assets/vendor/')

# Des noms assembles dans le code - « 'ti-arrow-' + (ouvert ? 'up' :
# 'right') » - qu'un releve de texte ne peut pas voir en entier.
ASSEMBLEES = ('ti-arrow-up', 'ti-arrow-right')


def telecharger(url, vers):
    if os.path.exists(vers):
        return vers
    if not os.path.isdir(os.path.dirname(vers)):
        os.makedirs(os.path.dirname(vers))
    print(u'telechargement : %s' % url)
    with urllib.request.urlopen(url) as r, open(vers, 'wb') as f:
        f.write(r.read())
    return vers


def noms_utilises():
    """Tous les « ti-… » ecrits dans le depot."""
    noms = set()
    for dossier, sous, fichiers in os.walk(RACINE):
        chemin = dossier.replace('\\', '/') + '/'
        if any(x in chemin for x in IGNORER):
            sous[:] = []
            continue
        for f in fichiers:
            if not f.endswith(EXTENSIONS):
                continue
            try:
                t = io.open(os.path.join(dossier, f), encoding='utf-8').read()
            except (UnicodeDecodeError, OSError):
                continue
            noms.update(re.findall(r'\bti-[a-z0-9]+(?:-[a-z0-9]+)*', t))
    noms.update(ASSEMBLEES)
    noms.discard('ti-arrow')   # moitie de nom, laissee par l'assemblage
    return noms


def table_des_icones(css):
    """Nom d'icone -> point de code, lu dans le CSS officiel."""
    table = {}
    for nom, code in re.findall(r'\.(ti-[a-z0-9-]+):before\{content:"\\([0-9a-f]{4})"\}', css):
        table[nom] = int(code, 16)
    return table


def main():
    css_src = io.open(telecharger(CSS_CDN, os.path.join(CACHE, 'tabler-%s.css' % VERSION)),
                      encoding='utf-8').read()
    woff_src = telecharger(FONT_CDN, os.path.join(CACHE, 'tabler-%s.woff2' % VERSION))

    table = table_des_icones(css_src)
    if not table:
        raise SystemExit(u'le CSS officiel n a pas pu etre lu')

    utilises = noms_utilises()
    gardes = sorted(n for n in utilises if n in table)
    manquants = sorted(n for n in utilises if n not in table and n != 'ti-icons')

    print(u'%d noms releves, %d retenus dans la police' % (len(utilises), len(gardes)))
    if manquants:
        print(u'ABSENTS de la police %s (ils ne s afficheront pas) :' % VERSION)
        for n in manquants:
            print(u'  - %s' % n)

    # ---- La police, reduite aux glyphes retenus ----
    from fontTools import subset
    if not os.path.isdir(VENDOR):
        os.makedirs(VENDOR)
    sortie_woff = os.path.join(VENDOR, 'tabler-amstc.woff2')
    options = subset.Options()
    options.flavor = 'woff2'
    options.desubroutinize = True
    options.layout_features = []
    options.name_IDs = ['*']
    options.notdef_outline = True
    police = subset.load_font(woff_src, options)
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=[table[n] for n in gardes])
    subsetter.subset(police)
    subset.save_font(police, sortie_woff, options)
    poids = os.path.getsize(sortie_woff) / 1024.0

    # ---- La feuille de style ----
    regles = u'\n'.join(u'.%s::before{content:"\\%04x";}' % (n, table[n]) for n in gardes)
    css = u'''/* Icones Tabler %s, reduites aux %d icones utilisees par le site.
   Fichier ENGENDRE par scripts/construire-icones.py : ne pas modifier a
   la main. Pour ajouter une icone, l'utiliser dans une page puis
   relancer le script. */
@font-face{
  font-family:"tabler-icons";
  font-style:normal;
  font-weight:400;
  font-display:swap;
  src:url("tabler-amstc.woff2?v=%s") format("woff2");
}
.ti{
  font-family:"tabler-icons" !important;
  speak:never; font-style:normal; font-weight:400; font-variant:normal;
  text-transform:none; line-height:1; display:inline-block;
  -webkit-font-smoothing:antialiased; -moz-osx-font-smoothing:grayscale;
}
%s
''' % (VERSION, len(gardes), VERSION, regles)
    io.open(os.path.join(VENDOR, 'tabler-amstc.css'), 'w', encoding='utf-8', newline='\n').write(css)

    print(u'assets/vendor/tabler-amstc.woff2 : %.1f Ko (contre 761 Ko pour la police entiere)' % poids)
    print(u'assets/vendor/tabler-amstc.css ecrit')
    return 1 if manquants else 0


if __name__ == '__main__':
    sys.exit(main())
