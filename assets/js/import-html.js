/**
 * Import d'un fichier HTML complet comme contenu (article, formation,
 * projet, étape, cours, leçon).
 *
 * LE BESOIN. Un cours ou un article est parfois rédigé ailleurs, sous
 * forme de page HTML autonome - avec son propre style, sa mise en page,
 * ses images encodées dedans. Le recopier dans l'éditeur du site
 * revenait à tout perdre : le style, les encadrés, les tableaux.
 *
 * CE QUE FAIT CE MODULE. Il lit le fichier, en garde ce qui doit l'être
 * et transforme ce qui ne peut pas passer tel quel :
 *
 *   1. Le TITRE vient de <title> ou du premier <h1>.
 *   2. Le CORPS est celui de <body>. Les <script>, <iframe>, <object>,
 *      <link>, formulaires et gestionnaires « on… » sont retirés : le
 *      site n'exécute jamais de code venu d'un fichier importé.
 *   3. Le STYLE est conservé mais CONFINÉ : chaque règle est préfixée
 *      par le sélecteur du bloc qui recevra le contenu, et les règles
 *      qui visent html/body/:root sont réécrites sur ce même bloc. Sans
 *      cela, le style du fichier repeindrait toute la page du site - la
 *      barre de menu, le pied de page. Les @font-face et @import
 *      externes sont écartés (pas de dépendance réseau tierce).
 *   4. Les IMAGES encodées en base64 sont EXTRAITES en fichiers : un
 *      Markdown ou une ligne de base de données de 180 Ko dont 120 de
 *      logo, ça se paie à chaque affichage et ça rend le contenu
 *      illisible dans l'éditeur. L'appelant fournit la fonction de
 *      dépôt (Storage Supabase ou dépôt Git) et reçoit une URL.
 *      Les images en URL absolue restent telles quelles ; les URL
 *      relatives sont signalées, elles ne pointeront nulle part.
 *
 * Le résultat est un HTML autonome que le rendu du site peut afficher
 * dans un bloc <div class="html-importe"> - avec DOMPurify configuré
 * pour laisser passer <style> et les attributs style, class, id.
 *
 * Utilisation :
 *   const r = await importerHtml(fichier, {
 *     deposerImage: async (blob, nom) => url,   // ou null : on garde le base64
 *     conteneur: '.html-importe',
 *   });
 *   r.titre, r.html, r.resume, r.images (nombre), r.avertissements[]
 */
(function () {
  "use strict";

  const CONTENEUR_DEFAUT = ".html-importe";

  function lireFichier(fichier) {
    return new Promise((resolve, reject) => {
      const lecteur = new FileReader();
      lecteur.onload = () => resolve(String(lecteur.result || ""));
      lecteur.onerror = () => reject(new Error("Lecture du fichier impossible."));
      lecteur.readAsText(fichier, "utf-8");
    });
  }

  function base64VersBlob(dataUrl) {
    const m = /^data:([^;,]+)(;base64)?,(.*)$/s.exec(dataUrl);
    if (!m) return null;
    const type = m[1] || "application/octet-stream";
    try {
      const brut = m[2] ? atob(m[3]) : decodeURIComponent(m[3]);
      const octets = new Uint8Array(brut.length);
      for (let i = 0; i < brut.length; i++) octets[i] = brut.charCodeAt(i);
      return new Blob([octets], { type });
    } catch (e) {
      return null;
    }
  }

  function extensionPour(type) {
    return ({ "image/png": "png", "image/jpeg": "jpg", "image/jpg": "jpg", "image/gif": "gif",
              "image/webp": "webp", "image/svg+xml": "svg", "image/avif": "avif" })[type] || "bin";
  }

  /**
   * Confine une feuille de style au conteneur.
   *
   * On ne réécrit pas le CSS à la main - trop de pièges - : on le laisse
   * ANALYSER PAR LE NAVIGATEUR (une feuille détachée dans un <style>
   * jetable), puis on parcourt les règles et on préfixe leurs sélecteurs.
   * Les @media et @supports sont parcourus récursivement ; @font-face,
   * @import et @keyframes-externes sont écartés ; @keyframes internes
   * gardés tels quels (ils ne ciblent rien).
   */
  function confinerCss(cssTexte, conteneur) {
    const feuille = document.createElement("style");
    feuille.media = "not all";            // jamais appliquée à la page hôte
    feuille.textContent = cssTexte;
    document.head.appendChild(feuille);
    let sortie = "";
    try {
      const marcher = (regles) => {
        let s = "";
        for (const r of regles) {
          if (r.type === CSSRule.STYLE_RULE) {
            const sel = r.selectorText.split(",").map((x) => {
              x = x.trim();
              // html / body / :root deviennent le conteneur lui-même.
              if (/^(html|body|:root)$/i.test(x)) return conteneur;
              // « body .truc » -> « .conteneur .truc »
              x = x.replace(/^(html\s+)?body\s+/i, conteneur + " ").replace(/^:root\s+/i, conteneur + " ");
              if (x.startsWith(conteneur)) return x;
              return conteneur + " " + x;
            }).join(", ");
            // La LARGEUR est décidée par le site, pas par le fichier. Un
            // fichier autonome fixe presque toujours « .page{max-width:980px;
            // margin:0 auto} » pour se centrer dans un navigateur ; confiné
            // dans une page qui fait déjà 1400, cette limite laisse un vide
            // de chaque côté - constaté sur le Mukhtasar. On retire
            // max-width et width des règles qui visent le conteneur
            // lui-même ou un bloc racine (.page, .container, .wrap, main),
            // et on garde tout le reste tel quel : les colonnes internes
            // ont le droit à leur largeur.
            let decl = r.style.cssText;
            const st = r.style;
            // Une COLONNE DE LECTURE se reconnaît à son centrage : max-width
            // + margin auto à gauche et à droite. C'est elle qui bride le
            // texte (« .corps{max-width:34rem;margin:0 auto} » sur le
            // Mukhtasar) ; on lève sa largeur. Un bloc racine nommé
            // (.page, .container…) aussi. Le reste - vignettes, encadrés,
            // colonnes latérales - garde sa largeur : elle a un sens.
            const centre = st.maxWidth && st.marginLeft === "auto" && st.marginRight === "auto";
            const racine = sel === conteneur
              || /^\S+ (\.(page|container|wrap|wrapper|content|main|site|corps|conteneur|shell)|main|article)$/i.test(sel);
            if (racine || centre) {
              decl = decl.replace(/(^|;)\s*(max-width|width|min-width)\s*:[^;]*;?/gi, "$1");
            }
            // position:fixed s'ancre sur la fenêtre, donc SORT du bloc
            // importé - un sommaire ou une barre du fichier viendrait se
            // coller par-dessus la barre du site. Rendu absolu, il reste
            // dans le conteneur (position:relative).
            decl = decl.replace(/position\s*:\s*fixed/gi, "position: absolute");
            s += sel + "{" + decl + "}\n";
          } else if (r.type === CSSRule.MEDIA_RULE || r.type === CSSRule.SUPPORTS_RULE) {
            const cond = r.type === CSSRule.MEDIA_RULE ? "@media " + r.conditionText : "@supports " + r.conditionText;
            s += cond + "{\n" + marcher(r.cssRules) + "}\n";
          } else if (r.type === CSSRule.KEYFRAMES_RULE) {
            s += r.cssText + "\n";
          }
          // FONT_FACE_RULE, IMPORT_RULE, NAMESPACE_RULE… : ignorés.
        }
        return s;
      };
      sortie = marcher(feuille.sheet.cssRules);
    } catch (e) {
      // Une feuille illisible : on préfère perdre le style que bloquer.
      sortie = "";
    } finally {
      feuille.remove();
    }
    return sortie;
  }

  async function importerHtml(fichier, options) {
    const opts = options || {};
    const conteneur = opts.conteneur || CONTENEUR_DEFAUT;
    const avertissements = [];
    const texte = await lireFichier(fichier);

    const doc = new DOMParser().parseFromString(texte, "text/html");

    // ---- Titre et résumé ----
    const h1 = doc.querySelector("h1");
    let titre = (doc.querySelector("title") && doc.querySelector("title").textContent.trim())
      || (h1 && h1.textContent.trim()) || "";
    // Les titres de page portent souvent le nom du site après un tiret :
    // « Prééclampsie - Clientelis Academia ». On garde la partie utile.
    titre = titre.replace(/\s+[-\u2013\u2014|]\s+[^-\u2013\u2014|]{2,40}$/, "").trim();
    const premierP = [...doc.querySelectorAll("p")].map((p) => p.textContent.trim()).find((t) => t.length > 40);
    const resume = premierP ? premierP.slice(0, 220).replace(/\s+/g, " ") : "";

    // ---- Nettoyage de sécurité ----
    doc.querySelectorAll("script, iframe, object, embed, form, input, button, textarea, select, link, meta, base, noscript").forEach((e) => e.remove());
    doc.querySelectorAll("*").forEach((e) => {
      for (const a of [...e.attributes]) {
        if (/^on/i.test(a.name)) e.removeAttribute(a.name);
        if ((a.name === "href" || a.name === "src") && /^\s*javascript:/i.test(a.value)) e.removeAttribute(a.name);
      }
    });

    // ---- Style : confiné au conteneur ----
    let css = "";
    doc.querySelectorAll("style").forEach((s) => { css += s.textContent + "\n"; s.remove(); });
    if (/@import|@font-face/i.test(css)) avertissements.push("Les polices externes (@import / @font-face) du fichier ont été écartées : le contenu utilisera les polices du site.");
    const cssConfine = css.trim() ? confinerCss(css, conteneur) : "";

    // ---- Images ----
    let nbImages = 0, nbExtraites = 0, nbRelatives = 0;
    const images = [...doc.querySelectorAll("img")];
    for (let i = 0; i < images.length; i++) {
      const img = images[i];
      const src = img.getAttribute("src") || "";
      nbImages++;
      if (/^data:image\//i.test(src)) {
        if (typeof opts.deposerImage === "function") {
          const blob = base64VersBlob(src);
          if (blob) {
            const nom = "image-" + String(i + 1).padStart(2, "0") + "." + extensionPour(blob.type);
            try {
              const url = await opts.deposerImage(blob, nom);
              if (url) { img.setAttribute("src", url); nbExtraites++; }
            } catch (e) {
              avertissements.push("Image " + (i + 1) + " : dépôt impossible (" + String(e.message || e).slice(0, 80) + "), conservée encodée dans le contenu.");
            }
          }
        }
      } else if (src && !/^(https?:)?\/\//i.test(src) && !src.startsWith("/")) {
        nbRelatives++;
      }
      // Une image sans texte de remplacement gêne les lecteurs d'écran ;
      // on ne peut pas deviner le bon, on met au moins l'attribut.
      if (!img.hasAttribute("alt")) img.setAttribute("alt", "");
      // Le style du fichier peut fixer des largeurs en pixels : sur
      // téléphone, l'image doit quand même tenir dans l'écran.
      img.style.maxWidth = "100%";
      img.style.height = "auto";
    }
    if (nbRelatives) avertissements.push(nbRelatives + " image(s) pointent vers un fichier local (chemin relatif) : elles ne s'afficheront pas. Encodez-les dans le fichier ou hébergez-les.");
    // Les CSS peuvent aussi porter des url(data:…) en fond : on les
    // laisse, ils sont plus rares et le confinement les garde intacts.

    // ---- Corps ----
    const corps = doc.body ? doc.body.innerHTML.trim() : texte;
    // position:relative + overflow:hidden : un élément absolu ou débordant
    // du contenu reste dans son bloc au lieu de recouvrir la page.
    const html = (cssConfine ? "<style>\n" + cssConfine + "</style>\n" : "")
      + '<div class="' + conteneur.replace(/^\./, "") + '" style="position:relative;overflow:hidden">\n' + corps + "\n</div>";

    return { titre, resume, html, images: nbImages, imagesExtraites: nbExtraites, avertissements };
  }

  /**
   * Configuration DOMPurify pour AFFICHER un contenu importé : on autorise
   * <style> et les attributs de présentation, que la configuration par
   * défaut retire. Le reste (scripts, gestionnaires) reste interdit -
   * l'import les a retirés, la purification les retirerait encore.
   */
  function optionsPurifyImport() {
    return {
      ADD_TAGS: ["style"],
      ADD_ATTR: ["style", "class", "id", "target", "colspan", "rowspan", "dir", "lang"],
      FORCE_BODY: true,
    };
  }

  /**
   * Confine APRÈS COUP un HTML déjà en base qui porte un <style> non
   * confiné - un contenu collé dans l'éditeur avant que l'import n'existe,
   * ou écrit à la main. Sans cela son style repeint la page entière :
   * c'est ce qui a mis le logo du Mukhtasar par-dessus la barre du site.
   *
   * Un contenu déjà confiné (classe html-importe) est rendu tel quel.
   * Un contenu sans <style> aussi : il n'a rien à confiner.
   */
  function confinerHtmlBrut(html, conteneur) {
    const c = conteneur || CONTENEUR_DEFAUT;
    const h = String(html || "");
    if (!/<style[\s>]/i.test(h) || h.indexOf('class="' + c.replace(/^\./, "") + '"') !== -1) return h;
    const doc = new DOMParser().parseFromString(h, "text/html");
    let css = "";
    doc.querySelectorAll("style").forEach((s) => { css += s.textContent + "\n"; s.remove(); });
    doc.querySelectorAll("script, iframe, object, embed, link").forEach((e) => e.remove());
    const cssConfine = css.trim() ? confinerCss(css, c) : "";
    // position:relative sur le conteneur : un élément du contenu en
    // position:absolute se cale alors sur le bloc importé, pas sur la page
    // - c'est ce qui posait un logo par-dessus la barre du site.
    return (cssConfine ? "<style>\n" + cssConfine + "</style>\n" : "")
      + '<div class="' + c.replace(/^\./, "") + '" style="position:relative;overflow:hidden">\n'
      + (doc.body ? doc.body.innerHTML : h) + "\n</div>";
  }

  /**
   * Un SOMMAIRE importé, sur téléphone, devient un dépliant.
   *
   * Un fichier autonome range souvent son sommaire dans une colonne
   * latérale et, sous une certaine largeur, le glisse hors écran pour le
   * rouvrir par un bouton et un script. L'import retire les scripts : le
   * sommaire reste là, invisible, sans rien pour l'ouvrir - constaté sur
   * le Mukhtasar. Le CSS confiné garde d'ailleurs ce « position:fixed »
   * devenu absolu et le « translateX(-101%) ».
   *
   * Cette fonction s'applique APRÈS le rendu, sur le bloc affiché : elle
   * repère la <nav> qui porte des liens d'ancre, la sort de son
   * positionnement, et la met dans un <details> replié en tête du
   * contenu. Un clic sur une entrée referme le dépliant et défile.
   * Sur grand écran, rien ne change : la colonne du fichier reste.
   *
   * À appeler par la page qui affiche : rendreSommaireDepliant(conteneur).
   */
  function rendreSommaireDepliant(racine, seuilPx) {
    const seuil = seuilPx || 1100;
    if (!racine || window.innerWidth >= seuil) return false;
    const bloc = racine.querySelector(".html-importe") || racine;
    // La nav « sommaire » : la première nav qui contient au moins trois
    // liens vers des ancres du même document.
    const navs = [...bloc.querySelectorAll("nav, aside, .toc, .sommaire, #sommaire")];
    const nav = navs.find((n) => n.querySelectorAll('a[href^="#"]').length >= 3);
    if (!nav || nav.closest("details.sommaire-mobile")) return false;

    const details = document.createElement("details");
    details.className = "sommaire-mobile";
    const summary = document.createElement("summary");
    const titre = nav.querySelector("h1, h2, h3, .toc-titre");
    summary.textContent = (titre && titre.textContent.trim()) || "Sommaire";
    details.appendChild(summary);

    // On déplace la nav telle quelle (ses styles internes servent encore
    // pour la liste), mais on annule tout ce qui la cachait ou la fixait.
    nav.style.cssText = "position:static !important; transform:none !important; display:block !important; width:auto !important; max-width:none !important; height:auto !important; max-height:none !important; overflow:visible !important; box-shadow:none !important; top:auto !important; left:auto !important; bottom:auto !important; flex:none !important; margin:0 !important; padding:8px 0 !important; background:transparent !important; z-index:auto !important;";
    if (titre) titre.style.display = "none";
    details.appendChild(nav);
    bloc.insertBefore(details, bloc.firstChild);

    // Un clic sur une entrée : on referme, et l'ancre fait le reste. Le
    // défilement doux est ajouté quand la cible existe.
    details.addEventListener("click", (e) => {
      const a = e.target.closest('a[href^="#"]');
      if (!a) return;
      const cible = bloc.querySelector(a.getAttribute("href")) || document.getElementById(a.getAttribute("href").slice(1));
      if (cible) {
        e.preventDefault();
        details.open = false;
        cible.scrollIntoView({ behavior: "smooth", block: "start" });
        history.replaceState(null, "", a.getAttribute("href"));
      }
    });
    // Le voile du fichier (fond sombre derrière le panneau) n'a plus lieu d'être.
    bloc.querySelectorAll(".voile, .overlay, .backdrop").forEach((v) => v.remove());
    return true;
  }

  window.importerHtml = importerHtml;
  window.optionsPurifyImport = optionsPurifyImport;
  window.confinerHtmlBrut = confinerHtmlBrut;
  window.rendreSommaireDepliant = rendreSommaireDepliant;
})();
