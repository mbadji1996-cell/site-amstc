# -*- coding: utf-8 -*-
u"""Les verts du site passent par des jetons, et non plus par des codes.

POURQUOI. La palette etait ecrite en clair, un peu partout : #17763B
revenait 230 fois, #06441C 180 fois, dans les feuilles comme dans les
styles des pages. Changer la couleur du site - pour Octobre Rose, par
exemple - demandait de reecrire ces centaines d'endroits, sans moyen de
revenir en arriere.

Chaque code devient donc l'appel d'un jeton, avec le code d'origine en
REPLI : var(--green, #17763B). Le repli n'est pas decoratif. Une page
qui ne definit pas le jeton rendrait la declaration invalide et
perdrait la propriete - c'est exactement le defaut documente en tete de
dark-mode.css. Avec le repli, une page qui ignore le jeton s'affiche
comme avant, au pixel pres.

CE QUI EST TOUCHE. Les fichiers .css, et les blocs <style> des pages.
PAS les attributs SVG (fill="#06441C") ni les balises meta, qui
n'acceptent pas var(). PAS non plus les lignes qui DEFINISSENT un jeton.

    python scripts/jetons-couleur.py           applique
    python scripts/jetons-couleur.py --lister  montre sans rien changer
"""
import io
import os
import re
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# code d'origine -> jeton. Les six verts de la charte, du plus sombre au
# plus clair ; les trois premiers composent les degrades des bandeaux.
JETONS = [
    ('#06441C', '--green-deep'),
    ('#0A5324', '--green-deep-2'),
    ('#12622F', '--green-deep-3'),
    ('#17763B', '--green'),
    ('#35B872', '--green-light'),
    ('#7FD9A0', '--green-soft'),
]

# Les pages d'apercu de partage (a/, f/, p/, e/, c/) et les bilans
# annuels sont ENGENDRES : les reecrire ici serait perdu a la
# prochaine reconstruction. Leurs gabarits vivent dans scripts/.
IGNORER = ('/node_modules/', '/.git/', '/assets/vendor/',
           '/a/', '/f/', '/p/', '/e/', '/c/', '/rapports/')
# Ces fichiers DEFINISSENT la palette : ils gardent leurs codes.
EXCEPTIONS = ('assets/css/octobre-rose.css',)


# Les teintes transparentes du vert vif - fonds de pastilles, auréoles
# d'icones - sont trop visibles pour rester vertes quand le reste rosit.
# rgba() accepte un var() qui porte les trois composantes.
RGBA = [
    (re.compile(r'rgba\(\s*23,\s*118,\s*59\s*,'), 'rgba(var(--green-rgb, 23,118,59),'),
    # Le vert profond : filets et ombres, mais surtout les voiles poses
    # sur les photos - banniere d'accueil, evenement phare, appel au don.
    (re.compile(r'rgba\(\s*6,\s*68,\s*28\s*,'), 'rgba(var(--green-deep-rgb, 6,68,28),'),
]


# Les seules definitions qui gardent leur code en clair : elles PORTENT
# la palette. Les autres - « --teal: #17763B », « --sidebar-bg:
# #06441C » - sont des alias, et doivent suivre.
CANONIQUES = {j for _, j in JETONS} | {'--green-rgb'}


def definition(texte, position):
    u"""Le code definit-il un jeton CANONIQUE (« --green: #17763B ») ?"""
    debut = texte.rfind('\n', 0, position) + 1
    m = re.search(r'(--[a-z0-9-]+)\s*:[^;{}]*$', texte[debut:position])
    return bool(m) and m.group(1) in CANONIQUES


def deja_jetonne(texte, position):
    u"""Le code est-il DEJA le repli d'un var() ?

    Sans ce garde-fou, relancer le script enveloppait chaque repli une
    fois de plus - var(--green, var(--green, #17763B)). Le rendu ne
    changeait pas, mais le fichier devenait illisible."""
    return bool(re.search(r'var\(--[a-z0-9-]+,\s*$', texte[max(0, position - 40):position]))


def remplacer(texte, zones, compte):
    u"""Reecrit les codes situes dans les zones donnees, de la fin au debut."""
    for code, jeton in JETONS:
        for m in reversed(list(re.finditer(re.escape(code), texte, re.I))):
            i = m.start()
            if not any(a <= i < b for a, b in zones):
                continue
            if definition(texte, i) or deja_jetonne(texte, i):
                continue
            texte = texte[:i] + 'var(%s, %s)' % (jeton, code) + texte[m.end():]
            compte[0] += 1
    for motif, remplacement in RGBA:
        for m in reversed(list(motif.finditer(texte))):
            if not any(a <= m.start() < b for a, b in zones):
                continue
            if definition(texte, m.start()) or deja_jetonne(texte, m.start()):
                continue
            texte = texte[:m.start()] + remplacement + texte[m.end():]
            compte[0] += 1
    return texte


def zones_css(texte):
    return [(m.start(), m.end()) for m in re.finditer(r'<style[^>]*>.*?</style>', texte, re.S)]


def fichiers():
    for dossier, sous, noms in os.walk(RACINE):
        c = dossier.replace('\\', '/') + '/'
        if any(x in c for x in IGNORER):
            sous[:] = []
            continue
        for n in sorted(noms):
            if n.endswith(('.css', '.html')) and not n.startswith('_'):
                p = os.path.join(dossier, n)
                rel = os.path.relpath(p, RACINE).replace('\\', '/')
                if rel not in EXCEPTIONS:
                    yield p, rel


def main():
    lister = '--lister' in sys.argv
    total = 0
    touches = 0
    for p, rel in fichiers():
        s = io.open(p, encoding='utf-8').read()
        sans_espace = s.replace(' ', '')
        if ('var(--green' in s and not re.search(r'#(06441C|17763B)', s, re.I)
                and 'rgba(23,118,59' not in sans_espace
                and 'rgba(6,68,28' not in sans_espace):
            continue
        zones = [(0, len(s))] if p.endswith('.css') else zones_css(s)
        if not zones:
            continue
        compte = [0]
        neuf = remplacer(s, zones, compte)
        if compte[0]:
            total += compte[0]
            touches += 1
            print(u'%-44s %3d' % (rel, compte[0]))
            if not lister:
                io.open(p, 'w', encoding='utf-8', newline='\n').write(neuf)
    print(u'\n%d codes remplaces dans %d fichiers%s'
          % (total, touches, u' (rien ecrit : --lister)' if lister else u''))

    # Ce qui reste en clair, pour que personne ne le croie oublie.
    restes = {}
    for p, rel in fichiers():
        s = io.open(p, encoding='utf-8').read()
        for code, _ in JETONS:
            for m in re.finditer(re.escape(code), s, re.I):
                if definition(s, m.start()):
                    continue
                zones = [(0, len(s))] if p.endswith('.css') else zones_css(s)
                if any(a <= m.start() < b for a, b in zones):
                    continue
                restes[code] = restes.get(code, 0) + 1
    if restes:
        print(u'\nCodes laisses en clair (attributs SVG, meta, scripts) :')
        for k, v in sorted(restes.items()):
            print(u'  %s : %d' % (k, v))
    return 0


if __name__ == '__main__':
    sys.exit(main())
