# -*- coding: utf-8 -*-
u"""Telecharge les bibliotheques externes et fait pointer les pages dessus.

POURQUOI. Le site chargeait huit bibliotheques depuis jsdelivr et unpkg.
Quand ces serveurs repondent mal - et cela arrive, c'est ce qui a efface
tous les pictogrammes du site - les consequences vont bien au-dela d'une
icone manquante : sans marked ni DOMPurify, un article ne s'affiche plus
du tout ; sans supabase-js, l'espace membres ne s'ouvre pas ; sans
decap-cms, on ne peut plus rien publier.

Deux d'entre elles n'etaient meme pas figees : « marked » et
« supabase-js@2 » suivaient la derniere version publiee. Une mise a jour
cassante serait arrivee sur le site sans que personne ne l'ait demandee.

CE QUE FAIT CE SCRIPT. Il telecharge chaque bibliotheque dans
assets/vendor/, a une version PRECISE, puis remplace l'adresse du CDN
dans toutes les pages par un chemin local - relatif a la profondeur de
la page.

POUR METTRE A JOUR une bibliotheque : changer sa version ci-dessous et
relancer

    python scripts/heberger-librairies.py

Les fichiers deja telecharges ne le sont pas deux fois ; passer
--refaire force le telechargement.
"""
import io
import os
import sys
import urllib.request

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(RACINE, 'assets', 'vendor')

# (fichier local, adresse a telecharger, adresses a remplacer dans les pages)
LIBRAIRIES = [
    ('supabase-js-2.117.1.min.js',
     'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.1/dist/umd/supabase.js',
     ['https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2']),

    ('marked-15.0.12.min.js',
     'https://cdn.jsdelivr.net/npm/marked@15.0.12/marked.min.js',
     ['https://cdn.jsdelivr.net/npm/marked/marked.min.js']),

    ('purify-3.4.16.min.js',
     'https://cdn.jsdelivr.net/npm/dompurify@3.4.16/dist/purify.min.js',
     ['https://cdn.jsdelivr.net/npm/dompurify@3/dist/purify.min.js']),

    ('xlsx-0.18.5.full.min.js',
     'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js',
     ['https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js']),

    ('qrcode-1.5.1.min.js',
     'https://cdn.jsdelivr.net/npm/qrcode@1.5.1/build/qrcode.min.js',
     ['https://cdn.jsdelivr.net/npm/qrcode@1.5.1/build/qrcode.min.js']),

    ('jspdf-2.5.1.umd.min.js',
     'https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js',
     ['https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js']),

    ('jspdf-autotable-3.8.2.min.js',
     'https://cdn.jsdelivr.net/npm/jspdf-autotable@3.8.2/dist/jspdf.plugin.autotable.min.js',
     ['https://cdn.jsdelivr.net/npm/jspdf-autotable@3.8.2/dist/jspdf.plugin.autotable.min.js']),

    ('chart-4.4.4.umd.min.js',
     'https://cdn.jsdelivr.net/npm/chart.js@4.4.4/dist/chart.umd.min.js',
     ['https://cdn.jsdelivr.net/npm/chart.js@4.4.4/dist/chart.umd.min.js']),

    ('decap-cms-3.14.1.js',
     'https://unpkg.com/decap-cms@3.14.1/dist/decap-cms.js',
     ['https://unpkg.com/decap-cms@3.14.1/dist/decap-cms.js']),
]

IGNORER = ('/node_modules/', '/.git/')


def telecharger(url, vers, refaire):
    if os.path.exists(vers) and not refaire:
        return os.path.getsize(vers), False
    if not os.path.isdir(os.path.dirname(vers)):
        os.makedirs(os.path.dirname(vers))
    requete = urllib.request.Request(url, headers={'User-Agent': 'amstc-site'})
    with urllib.request.urlopen(requete) as r, open(vers, 'wb') as f:
        f.write(r.read())
    return os.path.getsize(vers), True


def pages():
    for dossier, sous, fichiers in os.walk(RACINE):
        c = dossier.replace('\\', '/') + '/'
        if any(x in c for x in IGNORER):
            sous[:] = []
            continue
        for f in fichiers:
            if f.endswith('.html'):
                yield os.path.join(dossier, f)


def main():
    refaire = '--refaire' in sys.argv
    total = 0
    remplacements = {}

    for nom, url, anciennes in LIBRAIRIES:
        poids, neuf = telecharger(url, os.path.join(VENDOR, nom), refaire)
        total += poids
        print(u'%-34s %6.0f Ko %s' % (nom, poids / 1024.0, u'(telecharge)' if neuf else u'(deja la)'))
        for a in anciennes:
            remplacements[a] = nom

    touchees = 0
    for p in pages():
        s = io.open(p, encoding='utf-8').read()
        depart = s
        rel = os.path.relpath(p, RACINE).replace('\\', '/')
        prefixe = '../' * rel.count('/')
        for ancienne, nom in remplacements.items():
            s = s.replace(ancienne, prefixe + 'assets/vendor/' + nom)
        if s != depart:
            io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
            touchees += 1

    print(u'\n%d bibliotheques, %.1f Mo au total' % (len(LIBRAIRIES), total / 1048576.0))
    print(u'%d pages mises a jour' % touchees)

    # Ce qui reste appele a l'exterieur, pour que personne ne le decouvre
    # un jour de panne.
    restes = {}
    for p in pages():
        s = io.open(p, encoding='utf-8').read()
        for morceau in ('cdn.jsdelivr.net', 'unpkg.com', 'cdnjs.cloudflare.com'):
            if morceau in s:
                restes.setdefault(morceau, []).append(os.path.relpath(p, RACINE))
    if restes:
        print(u'\nAppels restants vers un serveur tiers :')
        for k, v in restes.items():
            print(u'  %-22s %d page(s) : %s' % (k, len(v), ', '.join(v[:3])))


if __name__ == '__main__':
    main()
